import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/theme_constants.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final TextEditingController _passwordCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final provider = Provider.of<PharmacyProvider>(context);
    final hasPassword = provider.masterPassword.isNotEmpty;

    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: Container(
          width: 500,
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.05), blurRadius: 20, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.security_rounded, color: Colors.white, size: 28),
                    SizedBox(width: 16),
                    Text("Backup & Security", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(32),
                  children: [
                    // MASTER PASSWORD SECTION
                    const Text("MASTER PASSWORD", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueGrey.shade100),
                      ),
                      child: Row(
                        children: [
                          Icon(hasPassword ? Icons.lock_outline : Icons.lock_open_rounded, color: hasPassword ? AppColors.success : Colors.orange),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(hasPassword ? "Master Password is Set" : "No Password Set (System Unprotected)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(hasPassword ? "Required for sensitive actions like deletions." : "Create a PIN to enable protection toggles below.", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: hasPassword ? Colors.redAccent : AppColors.primary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                            ),
                            onPressed: () => _showPasswordDialog(context, provider),
                            child: Text(hasPassword ? "RESET PIN" : "CREATE PIN", style: const TextStyle(color: Colors.white)),
                          )
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // 1. INVOICE & DAILY LOCK SECURITY
                    const Text("1. INVOICE & DAILY LOCK SECURITY", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.5)),
                    const SizedBox(height: 16),
                    _buildToggle(
                      title: "Lock Previous Day Edits",
                      subtitle: "Disables modifying, editing, or deleting any sale or purchase invoice dated prior to today without Master PIN.",
                      icon: Icons.calendar_today_rounded,
                      value: provider.securityToggles['lock_previous_day_edits'] ?? true,
                      onChanged: (val) => provider.updateSecurityToggle('lock_previous_day_edits', val),
                      isDisabled: false,
                    ),
                    _buildToggle(
                      title: "Require PIN for Deleting Sales Bills",
                      subtitle: "Prompts for Master PIN before a user can permanently delete or cancel a sales invoice.",
                      icon: Icons.delete_sweep_rounded,
                      value: provider.securityToggles['require_pin_delete_sales'] ?? false,
                      onChanged: (val) => provider.updateSecurityToggle('require_pin_delete_sales', val),
                      isDisabled: !hasPassword,
                    ),
                    _buildToggle(
                      title: "Require PIN for Deleting Purchases",
                      subtitle: "Restricts removing existing purchase invoices to prevent unauthorized stock reductions.",
                      icon: Icons.shopping_cart_checkout_rounded,
                      value: provider.securityToggles['require_pin_delete_purchases'] ?? false,
                      onChanged: (val) => provider.updateSecurityToggle('require_pin_delete_purchases', val),
                      isDisabled: !hasPassword,
                    ),
                    _buildToggle(
                      title: "Require PIN for Discounts Above Threshold",
                      subtitle: "Prompts for authorization if an employee attempts to give a discount higher than your set limit (e.g., > 10%).",
                      icon: Icons.percent_rounded,
                      value: provider.securityToggles['require_pin_discount_threshold'] ?? false,
                      onChanged: (val) => provider.updateSecurityToggle('require_pin_discount_threshold', val),
                      isDisabled: !hasPassword,
                    ),

                    const SizedBox(height: 32),

                    // 2. INVENTORY & STOCK CONTROLS
                    const Text("2. INVENTORY & STOCK CONTROLS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.5)),
                    const SizedBox(height: 16),
                    _buildToggle(
                      title: "Require PIN for Stock Adjustments",
                      subtitle: "Locks manual stock quantity additions or subtractions in the Stock Adjustment module.",
                      icon: Icons.settings_suggest_rounded,
                      value: provider.securityToggles['require_pin_stock_adjustments'] ?? false,
                      onChanged: (val) => provider.updateSecurityToggle('require_pin_stock_adjustments', val),
                      isDisabled: !hasPassword,
                    ),
                    _buildToggle(
                      title: "Require PIN for Adding New Agent (Stock Check)",
                      subtitle: "Prompts for admin PIN before adding an extra verification agent in the Stock Checking window.",
                      icon: Icons.person_add_alt_1_rounded,
                      value: provider.securityToggles['require_pin_add_agent_stock_check'] ?? true,
                      onChanged: (val) => provider.updateSecurityToggle('require_pin_add_agent_stock_check', val),
                      isDisabled: !hasPassword,
                    ),
                    _buildToggle(
                      title: "Require PIN for Admin Stock Adjustment",
                      subtitle: "Locks the consolidated 'Adjustment (Admin)' view in Stock Checking behind a PIN.",
                      icon: Icons.admin_panel_settings_rounded,
                      value: provider.securityToggles['require_pin_admin_stock_adjustment'] ?? true,
                      onChanged: (val) => provider.updateSecurityToggle('require_pin_admin_stock_adjustment', val),
                      isDisabled: !hasPassword,
                    ),
                    _buildToggle(
                      title: "Require PIN for Writing Off Damaged/Expired Stock",
                      subtitle: "Prevents unauthorized removal of inventory logged under damage or expiry write-offs.",
                      icon: Icons.broken_image_rounded,
                      value: provider.securityToggles['require_pin_write_off'] ?? false,
                      onChanged: (val) => provider.updateSecurityToggle('require_pin_write_off', val),
                      isDisabled: !hasPassword,
                    ),
                    _buildToggle(
                      title: "Require PIN for Merging Duplicate Products",
                      subtitle: "Protects against accidental or unauthorized consolidation of product masters and batch histories.",
                      icon: Icons.call_merge_rounded,
                      value: provider.securityToggles['require_pin_merge_products'] ?? false,
                      onChanged: (val) => provider.updateSecurityToggle('require_pin_merge_products', val),
                      isDisabled: !hasPassword,
                    ),
                    _buildToggle(
                      title: "Require PIN for Changing Medicine Selling Rates / MRP",
                      subtitle: "Restricts staff from manually overriding selling prices or MRP during sales entry or in product master.",
                      icon: Icons.currency_exchange_rounded,
                      value: provider.securityToggles['require_pin_change_rates'] ?? false,
                      onChanged: (val) => provider.updateSecurityToggle('require_pin_change_rates', val),
                      isDisabled: !hasPassword,
                    ),

                    const SizedBox(height: 32),

                    // 3. MASTER DATA & REPORTS SECURITY
                    const Text("3. MASTER DATA & REPORTS SECURITY", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.5)),
                    const SizedBox(height: 16),
                    _buildToggle(
                      title: "Require PIN for Editing Customer / Supplier Master",
                      subtitle: "Prompts for PIN before altering supplier bank details, customer credit balances, or contact info.",
                      icon: Icons.assignment_ind_rounded,
                      value: provider.securityToggles['require_pin_edit_master'] ?? false,
                      onChanged: (val) => provider.updateSecurityToggle('require_pin_edit_master', val),
                      isDisabled: !hasPassword,
                    ),
                    _buildToggle(
                      title: "Lock Financial & Tax Reports",
                      subtitle: "Restricts access to GSTR-1, GSTR-3B, Profit & Loss, and Margin reports behind the Master PIN.",
                      icon: Icons.bar_chart_rounded,
                      value: provider.securityToggles['require_pin_financial_reports'] ?? false,
                      onChanged: (val) => provider.updateSecurityToggle('require_pin_financial_reports', val),
                      isDisabled: !hasPassword,
                    ),
                    _buildToggle(
                      title: "Require PIN for Database Reset or Bulk CSV Imports",
                      subtitle: "Adds a high-security lock before performing database wipes, inventory resets, or bulk updates.",
                      icon: Icons.upload_file_rounded,
                      value: provider.securityToggles['require_pin_db_reset_imports'] ?? false,
                      onChanged: (val) => provider.updateSecurityToggle('require_pin_db_reset_imports', val),
                      isDisabled: !hasPassword,
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

  Widget _buildToggle({required String title, required String subtitle, required IconData icon, required bool value, required Function(bool) onChanged, required bool isDisabled}) {
    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12)
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ),
            ),
            Switch(
              value: value,
              activeTrackColor: AppColors.success,
              onChanged: isDisabled ? null : onChanged,
            )
          ],
        ),
      ),
    );
  }

  void _showPasswordDialog(BuildContext context, PharmacyProvider provider) {
    _passwordCtrl.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(provider.masterPassword.isEmpty ? "Create Master Password" : "Reset Master Password", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: InputDecoration(
            hintText: "Enter a strong PIN or Password",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              if (_passwordCtrl.text.trim().isNotEmpty) {
                provider.setMasterPassword(_passwordCtrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text("SAVE PASSWORD", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }
}
