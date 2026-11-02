import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/theme_constants.dart';
import '../utils/tax_calculator.dart';
import '../widgets/draggable_modal.dart';
import '../utils/watchdog_mixin.dart';
import '../services/update_checker_service.dart';
import '../services/excel_worker_service.dart';
import 'printer_customization_screen.dart';
import 'edited_invoices_screen.dart';
import 'server_settings_screen.dart';
import 'settings/database_backup_tab.dart';
import 'settings/excel_reports_tab.dart';
import 'settings/security_permissions_tab.dart';
import '../widgets/purchase_rule_config_dialog.dart';

class SettingsScreen extends StatefulWidget {
  final String? initialTab;
  const SettingsScreen({super.key, this.initialTab});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WatchdogMixin<SettingsScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _gstCtrl;
  late TextEditingController _githubRepoCtrl;
  late TextEditingController _githubTokenCtrl;
  int _minExpiryMonths = 6;
  String _activeTab = "Pharmacy Profile";

  Set<String> _selectedResetCategoryIds = {
    'products',
    'batches',
    'sales',
    'purchases',
    'sales_returns',
    'purchase_returns',
    'prescriptions_adjustments',
    'damages',
    'patients',
    'suppliers_doctors',
    'customer_account',
    'wholesale_account',
    'accounts_daybook',
    'vouchers',
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null) {
      _activeTab = widget.initialTab == "Security & Backup" ? "Database & Backups" : widget.initialTab!;
    }
    final profile = Provider.of<PharmacyProvider>(context, listen: false).companyProfile;
    _nameCtrl = TextEditingController(text: profile.name);
    _addressCtrl = TextEditingController(text: profile.address);
    _phoneCtrl = TextEditingController(text: profile.phone);
    _gstCtrl = TextEditingController(text: profile.gstIn);
    _githubRepoCtrl = TextEditingController(text: "jiyadpn0/pharmacy_app");
    _githubTokenCtrl = TextEditingController();
    _loadGitHubRepoSetting();
  }

  Future<void> _loadGitHubRepoSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRepo = prefs.getString('github_repo_path');
    final savedToken = prefs.getString('github_token');
    final savedExpiryMonths = prefs.getInt('min_purchase_expiry_months') ?? 6;
    if (mounted) {
      setState(() {
        if (savedRepo != null && savedRepo.isNotEmpty) {
          _githubRepoCtrl.text = savedRepo;
        }
        if (savedToken != null && savedToken.isNotEmpty) {
          _githubTokenCtrl.text = savedToken;
        }
        _minExpiryMonths = savedExpiryMonths;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _gstCtrl.dispose();
    _githubRepoCtrl.dispose();
    _githubTokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PharmacyProvider>(context);
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.background,
      body: Row(
        children: [
          _buildSettingsSidebar(),
          Expanded(
            child: (_activeTab == "Edited Invoices" || _activeTab == "Cloud & Server Sync")
                ? Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_activeTab.toUpperCase(), style: AppStyles.labelOf(context).copyWith(fontSize: 12, letterSpacing: 2)),
                  const SizedBox(height: 32),
                  Expanded(
                    child: _activeTab == "Edited Invoices"
                        ? const EditedInvoicesScreen(headless: true)
                        : const ServerSettingsScreen(embedInTab: true),
                  ),
                ],
              ),
            )
                : SingleChildScrollView(
              padding: const EdgeInsets.all(48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_activeTab.toUpperCase(), style: AppStyles.labelOf(context).copyWith(fontSize: 12, letterSpacing: 2)),
                  const SizedBox(height: 32),
                  if (_activeTab == "Pharmacy Profile") _buildProfileSettings(),
                  if (_activeTab == "Database & Backups")
                    DatabaseBackupTab(
                      showSnackBar: _showSnackBar,
                      showErrorDialog: _showErrorDialog,
                      checkGitHubUpdates: _checkGitHubUpdates,
                    ),
                  if (_activeTab == "Excel Reports & Tools")
                    ExcelReportsTab(
                      availableFinancialYears: provider.availableFinancialYears,
                      handleSync: _handleSync,
                      handleDelete: _handleDelete,
                      showSnackBar: _showSnackBar,
                      showErrorDialog: _showErrorDialog,
                      showProgressDialog: _showProgressDialog,
                    ),
                  if (_activeTab == "Security & Permissions")
                    SecurityPermissionsTab(
                      showPasswordDialog: _showPasswordDialog,
                    ),
                  if (_activeTab == "Validation Rules")
                    const SizedBox(height: 540, child: ValidationRuleManagerWidget()),
                  if (_activeTab == "Print Customization") _buildPrintSettings(),
                  if (_activeTab == "Fiscal Calendar") _buildFiscalCalendarSettings(provider),
                  if (_activeTab == "Database Reset & Wipe") _buildDatabaseResetSettings(context, provider),
                  if (_activeTab == "User Accounts")
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: AppStyles.cardDecorationOf(context),
                      child: Text("Logged in as Administrator (Local Standalone Station)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: c.primaryText)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSidebar() {
    final c = AppColors.of(context);
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: c.sidebarBg,
        border: Border(right: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.settings_suggest_rounded, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 16),
              const Text("SYSTEM HUB", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _settingsTab("Pharmacy Profile", Icons.store_rounded),
                  _settingsTab("Cloud & Server Sync", Icons.cloud_sync_rounded),
                  _settingsTab("Database & Backups", Icons.shield_rounded),
                  _settingsTab("Excel Reports & Tools", Icons.table_chart_rounded),
                  _settingsTab("Security & Permissions", Icons.admin_panel_settings_rounded),
                  _settingsTab("Validation Rules", Icons.palette_rounded),
                  _settingsTab("Fiscal Calendar", Icons.calendar_month_rounded),
                  _settingsTab("Edited Invoices", Icons.history_rounded),
                  _settingsTab("Print Customization", Icons.print_rounded),
                  _settingsTab("User Accounts", Icons.people_alt_rounded),
                  _settingsTab("Database Reset & Wipe", Icons.delete_forever_rounded, isDanger: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _actionBtn("SAVE ALL CHANGES", Icons.check_circle_rounded, AppColors.success, onTap: _saveSettings),
        ],
      ),
    );
  }

  Widget _settingsTab(String label, IconData icon, {bool isDanger = false}) {
    bool isActive = _activeTab == label;
    return InkWell(
      onTap: () => setState(() => _activeTab = label),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isActive ? (isDanger ? Colors.red.shade50 : Colors.white) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isDanger ? Border.all(color: Colors.red.shade300, width: 1) : null,
          boxShadow: isActive ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))] : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isDanger ? Colors.red : (isActive ? AppColors.secondary : Colors.blueGrey.shade300)),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w900 : FontWeight.w600, color: isDanger ? Colors.red.shade800 : (isActive ? AppColors.primary : Colors.blueGrey.shade600))),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Official Information", "Basic store details for invoice branding."),
        const SizedBox(height: 24),
        _buildInputCard([
          _buildTextField("Pharmacy Name*", _nameCtrl, isCyan: true),
          const SizedBox(height: 24),
          _buildTextField("Full Address", _addressCtrl, maxLines: 3),
        ]),
        const SizedBox(height: 32),
        _buildSectionHeader("Legal & Tax", "Mandatory information for government compliance."),
        const SizedBox(height: 24),
        _buildInputCard([
          Row(
            children: [
              Expanded(child: _buildTextField("Contact Number", _phoneCtrl)),
              const SizedBox(width: 24),
              Expanded(child: _buildTextField("GSTIN Number", _gstCtrl)),
            ],
          ),
        ]),
        _buildSystemUpdateSection(),
      ],
    );
  }

  Widget _buildFiscalCalendarSettings(PharmacyProvider provider) {
    DateTime openingDate = provider.softwareOpeningDate;
    String formattedOpeningDate = DateFormat('dd MMMM yyyy').format(openingDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          "Fiscal Calendar & Software Opening Date",
          "Set your software opening date to generate all fiscal years, and switch active financial years.",
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: AppStyles.cardDecorationOf(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.event_available_rounded, color: Colors.teal.shade700, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Software Opening Date", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(
                          "All financial years from this opening date onwards are automatically calculated.",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: openingDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                        helpText: "Select Software Opening Date",
                      );
                      if (picked != null) {
                        await provider.setSoftwareOpeningDate(picked);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.green,
                            content: Text("Software Opening Date updated to ${DateFormat('dd MMMM yyyy').format(picked)}!"),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                    label: Text(formattedOpeningDate, style: const TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: AppStyles.cardDecorationOf(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_rounded, color: Colors.teal, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            "Current Active Financial Year: ${provider.selectedFinancialYear}",
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.teal),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Generated starting from Opening Date (${DateFormat('dd/MM/yyyy').format(openingDate)}) — Sorted Newest First",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 32),
              const Text(
                "AVAILABLE FINANCIAL YEARS (NEWEST ON TOP)",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey, letterSpacing: 1),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: provider.availableFinancialYears.map((fy) {
                  bool isActive = provider.selectedFinancialYear == fy;

                  int startY = 2021;
                  List<String> parts = fy.split('-');
                  if (parts.isNotEmpty) {
                    startY = int.tryParse(parts.first) ?? 2021;
                  }
                  String dateRangeStr = "01 Apr $startY – 31 Mar ${startY + 1}";

                  return InkWell(
                    onTap: () => provider.setSelectedFinancialYear(fy),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 280,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.teal.shade50 : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive ? Colors.teal : Colors.grey.shade300,
                          width: isActive ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isActive ? Icons.check_circle_rounded : Icons.calendar_today_rounded,
                            color: isActive ? Colors.teal : Colors.grey.shade500,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      fy,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: isActive ? Colors.teal.shade900 : Colors.black87,
                                      ),
                                    ),
                                    if (isActive) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.teal,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          "ACTIVE",
                                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(dateRangeStr, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSystemUpdateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 48),
        _buildSectionHeader("System & Version Control", "Maintain your ERP software and check for updates via GitHub Releases."),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: AppStyles.cardDecorationOf(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.system_update_rounded, color: Colors.blue, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Sahakar Medicals ERP", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text("Version ${UpdateCheckerService.currentVersion} (Commercial Build • Stable)", style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _checkGitHubUpdates,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text("CHECK UPDATES", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade800,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Icon(Icons.code_rounded, size: 18, color: Colors.blueGrey),
                        const SizedBox(width: 8),
                        const Text("GitHub Repository:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 280,
                          child: TextField(
                            controller: _githubRepoCtrl,
                            decoration: InputDecoration(
                              hintText: "username/repository",
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text("(Format: owner/repo)", style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Icon(Icons.key_rounded, size: 18, color: Colors.blueGrey),
                        const SizedBox(width: 8),
                        const Text("GitHub Access Token:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 280,
                          child: TextField(
                            controller: _githubTokenCtrl,
                            obscureText: true,
                            decoration: InputDecoration(
                              hintText: "ghp_xxxxxxxxxxxx (Optional for auto-issue posting)",
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.save, size: 14),
                          label: const Text("Save Credentials", style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            backgroundColor: Colors.blueGrey.shade700,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('github_repo_path', _githubRepoCtrl.text.trim());
                            await prefs.setString('github_token', _githubTokenCtrl.text.trim());
                            await prefs.setInt('min_purchase_expiry_months', _minExpiryMonths);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("System settings & credentials saved successfully!"),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Icon(Icons.timer_rounded, size: 18, color: Colors.blueGrey),
                        const SizedBox(width: 8),
                        const Text("Min Purchase Expiry Threshold:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                        const SizedBox(width: 10),
                        DropdownButton<int>(
                          value: _minExpiryMonths,
                          items: const [
                            DropdownMenuItem(value: 3, child: Text("3 Months")),
                            DropdownMenuItem(value: 6, child: Text("6 Months (Recommended)")),
                            DropdownMenuItem(value: 9, child: Text("9 Months")),
                            DropdownMenuItem(value: 12, child: Text("12 Months")),
                          ],
                          onChanged: (val) async {
                            if (val != null) {
                              setState(() => _minExpiryMonths = val);
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setInt('min_purchase_expiry_months', val);
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                        const Text("(Triggers Distributor Return Warning during purchase)", style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _checkGitHubUpdates() async {
    final repoPath = _githubRepoCtrl.text.trim();
    if (repoPath.isEmpty || !repoPath.contains('/') || repoPath == "owner/repository") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a valid GitHub repository path (e.g. 'username/pharmacy_app')."),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('github_repo_path', repoPath);

    if (!mounted) return;
    await UpdateCheckerService.checkForUpdates(context, silent: false, repoPath: repoPath);
  }

  Future<void> _handleSync({
    required String title,
    required Future<dynamic> Function(PharmacyProvider p, String path, Function(double, String) progress, String? fy) action,
    required bool isExport,
    required PharmacyProvider provider,
    String? financialYear,
  }) async {
    String? filePath;

    if (isExport) {
      String defaultFileName = "${title.toLowerCase().replaceAll(' ', '_')}_${financialYear ?? 'all_years'}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx";
      filePath = await FilePicker.saveFile(
        dialogTitle: 'Select where to save $title Export:',
        fileName: defaultFileName,
        allowedExtensions: ['xlsx'],
      );
    } else {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );
      if (result != null) filePath = result.files.single.path;
    }

    if (filePath == null) return;

    if (!isExport) {
      if (!mounted) return;

      Map<String, dynamic>? analysis;
      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Center(
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 8,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 36, vertical: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 20),
                      Text("Analyzing File...", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      SizedBox(height: 8),
                      Text("Press ESC to cancel / go back", style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        analysis = await provider.analyzeExcelForImport(filePath);
      } finally {
        if (mounted && context.mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }

      if (!mounted || !context.mounted) return;
      if (analysis['success'] != true) {
        if (analysis['message'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text(analysis['message'] ?? "Analysis Failed")),
          );
        }
        return;
      }

      if (analysis['success'] == true) {
        bool isReturn = title.toLowerCase().contains("return");
        bool isSales = title.toLowerCase().contains("sales") && !isReturn;
        bool isPurchase = title.toLowerCase().contains("purchase") && !isReturn;
        bool isDamage = title.toLowerCase().contains("damage");
        bool isInventory = title.toLowerCase().contains("inventory");
        bool isProductMaster = title.toLowerCase().contains("product master") || title.toLowerCase().contains("product");

        dynamic result = await _showImportPreview(analysis, isSales: isSales, isPurchase: isPurchase, isReturn: isReturn, isDamage: isDamage, isInventory: isInventory, isProductMaster: isProductMaster, title: title);
        if (result == null || !mounted || !context.mounted) return;

        Map<String, int>? customMapping;
        if (result is Map<String, int>) {
          customMapping = result;
        }

        final selectedPath = filePath;
        provider.addSyncTask(
          title: title,
          type: 'Import',
          cachedFilePath: selectedPath,
          taskRunner: (onProgress) async {
            if (isSales) {
              return await provider.importSalesFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping, financialYear: financialYear);
            } else if (isPurchase) {
              return await provider.importPurchaseFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping, financialYear: financialYear);
            } else if (isReturn) {
              if (title.toLowerCase().contains("sales")) {
                return await provider.importSalesReturnsFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping, financialYear: financialYear);
              } else if (title.toLowerCase().contains("purchase")) {
                return await provider.importPurchaseReturnsFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping, financialYear: financialYear);
              } else {
                return await provider.importReturnsFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping, financialYear: financialYear);
              }
            } else if (isDamage) {
              return await provider.importDamageFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping);
            } else if (isInventory) {
              return await provider.importInventoryFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping);
            } else if (isProductMaster) {
              return await provider.importProductMasterFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping);
            } else {
              return await action(provider, selectedPath, onProgress, financialYear);
            }
          },
        );

        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.blue.shade800,
              content: Text("⚡ '$title' added to Background Sync Queue! You can continue working."),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(analysis['message'] ?? "Analysis Failed")));
      }
    } else {
      final selectedPath = filePath;
      provider.addSyncTask(
        title: title,
        type: 'Export',
        cachedFilePath: selectedPath,
        taskRunner: (onProgress) async {
          final res = await action(provider, selectedPath, onProgress, financialYear);
          if (res is Map<String, dynamic>) return res;
          return {'success': true, 'message': '$title exported successfully.'};
        },
      );

      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.blue.shade800,
            content: Text("⚡ '$title' running in background! You can continue working."),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _handleDelete({
    required String title,
    required Future<dynamic> Function(PharmacyProvider p, String? fy) deleteAction,
    required PharmacyProvider provider,
    String? financialYear,
  }) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Confirm Delete: $title"),
        content: Text("Are you sure you want to delete all records for '$title' (${financialYear ?? 'All Years'})? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("DELETE"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    provider.addSyncTask(
      title: "Delete $title",
      type: 'Delete',
      taskRunner: (onProgress) async {
        onProgress(0.5, "Deleting records...");
        return await deleteAction(provider, financialYear);
      },
    );

    if (mounted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade800,
          content: Text("⚡ Deleting '$title' in background..."),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<dynamic> _showImportPreview(Map<String, dynamic> analysis, {bool isSales = false, bool isPurchase = false, bool isReturn = false, bool isDamage = false, bool isInventory = false, bool isProductMaster = false, String? title}) async {
    Map<String, String> salesFields = {
      'invoice_no': 'Entry No',
      'date': 'Date',
      'time': 'Time',
      'patient': 'Patient/Customer',
      'doctor': 'Doctor',
      'mobile': 'Mobile No',
      'account': 'Account/Type',
      'agent': 'Sales Agent',
      'done_by': 'Done By',
      'product': 'Product Name',
      'packing': 'Packing',
      'batch': 'Batch',
      'expiry': 'Expiry',
      'qty': 'Quantity',
      'mrp': 'MRP',
      'total': 'Grand Total',
      'disc_perc': 'Discount %',
      'disc_amt': 'Discount Amt',
      'gst_perc': 'GST %',
      'gst_amt': 'GST Amt',
      'profit': 'Profit',
    };

    Map<String, String> purchaseFields = {
      'entry_no': 'Entry No',
      'date': 'Date',
      'time': 'Time',
      'supplier': 'Supplier',
      'inv_no': 'Invoice No',
      'inv_date': 'Inv Date',
      'product': 'Product Name',
      'done_by': 'Done By',
      'packing': 'Packing',
      'batch': 'Batch',
      'expiry': 'Expiry',
      'qty': 'Quantity',
      'f_qty': 'Free Qty',
      'mrp': 'MRP',
      'p_rate': 'P.Rate',
      'total': 'Grand Total',
      'disc_perc': 'Discount %',
      'disc_amt': 'Discount Amt',
      'gst_perc': 'GST %',
      'gst_amt': 'GST Amt',
    };

    Map<String, String> returnFields = {
      'entry_no': 'Entry No',
      'date': 'Date',
      'customer': 'Customer/Supplier',
      'product': 'Product Name',
      'packing': 'Packing',
      'batch': 'Batch',
      'qty': 'Quantity',
      'ref_invoice': 'Ref Invoice/Purchase',
      'net': 'Taxable Amount',
      'disc_amt': 'Discount Amt',
      'disc_perc': 'Discount %',
      'gst_perc': 'GST %',
      'gst_amt': 'GST Amt',
      'grand_total': 'Grand Total',
    };

    Map<String, String> damageFields = {
      'id': 'ID',
      'date': 'Date',
      'product': 'Product Name',
      'packing': 'Packing',
      'batch': 'Batch',
      'qty': 'Quantity',
      'reason': 'Reason',
      'loss_value': 'Loss Value',
    };

    Map<String, String> inventoryFields = {
      'name': 'Name',
      'packing': 'Packing',
      'stock': 'Stock',
      'batch': 'Batch',
      'expiry': 'Expiry',
      'mrp': 'MRP',
      'l_cost': 'L Cost',
      'mrp_value': 'MRP Value',
      'supplier': 'Supplier',
      'gst': 'Gst%',
      'category': 'Category',
      'sub_category': 'Sub Category',
    };

    Map<String, String> productMasterFields = {
      'name': 'Name',
      'packing': 'Packing',
      'rack': 'RACK',
      'hsncode': 'hsncode',
      'mrp': 'MRP',
      'p_rate': 'P.RATE',
      'patent': 'Patent',
      'generic_name': 'Generic Name',
      'gst': 'Gst',
      'category': 'Category',
      'sub_category': 'Sub Category',
      'sdisc': 'Sdisc%',
      'schedule': 'Schedule',
    };

    Map<String, String> activeFields = {};
    List<String> fieldOrder = [];

    if (isSales) {
      activeFields = salesFields;
      fieldOrder = ['invoice_no', 'date', 'time', 'patient', 'mobile', 'account', 'agent', 'done_by', 'product', 'packing', 'doctor', 'batch', 'expiry', 'qty', 'mrp', 'total', 'disc_perc', 'disc_amt', 'gst_perc', 'gst_amt', 'profit'];
    } else if (isPurchase) {
      activeFields = purchaseFields;
      fieldOrder = ['entry_no', 'date', 'time', 'supplier', 'inv_no', 'inv_date', 'done_by', 'product', 'packing', 'batch', 'expiry', 'qty', 'f_qty', 'mrp', 'p_rate', 'total', 'disc_perc', 'disc_amt', 'gst_perc', 'gst_amt'];
    } else if (isReturn) {
      activeFields = returnFields;
      fieldOrder = ['entry_no', 'date', 'customer', 'product', 'packing', 'batch', 'qty', 'ref_invoice', 'net', 'disc_amt', 'disc_perc', 'gst_perc', 'gst_amt', 'grand_total'];
    } else if (isDamage) {
      activeFields = damageFields;
      fieldOrder = ['id', 'date', 'product', 'packing', 'batch', 'qty', 'reason', 'loss_value'];
    } else if (isInventory) {
      activeFields = inventoryFields;
      fieldOrder = ['name', 'packing', 'stock', 'batch', 'expiry', 'mrp', 'l_cost', 'mrp_value', 'supplier', 'gst', 'category', 'sub_category'];
    } else if (isProductMaster) {
      activeFields = productMasterFields;
      fieldOrder = ['name', 'packing', 'rack', 'hsncode', 'mrp', 'p_rate', 'patent', 'generic_name', 'gst', 'category', 'sub_category', 'sdisc', 'schedule'];
    }

    String importTypeKey = (isReturn && title != null && title.toLowerCase().contains("sales"))
        ? "sales_return"
        : (isReturn && title != null && title.toLowerCase().contains("purchase"))
        ? "purchase_return"
        : isSales
        ? "sales"
        : isPurchase
        ? "purchase"
        : isReturn
        ? "return"
        : isDamage
        ? "damage"
        : isInventory
        ? "inventory"
        : isProductMaster
        ? "product_master"
        : "general";

    Map<String, dynamic> currentAnalysis = analysis;
    final List<String> rawHeaders = List<String>.from(currentAnalysis['headers'] ?? []);
    Map<String, int?> fieldMapping = {};

    Future<void> autoMapFields(List<String> excelHeaders) async {
      Map<String, dynamic> savedHeaderMappings = {};
      try {
        final prefs = await SharedPreferences.getInstance();
        String? savedJson = prefs.getString("excel_import_header_mapping_$importTypeKey");
        if (savedJson == null || savedJson.isEmpty) {
          savedJson = prefs.getString("excel_import_header_mapping_global");
        }
        if (savedJson != null && savedJson.isNotEmpty) {
          savedHeaderMappings = jsonDecode(savedJson);
        }
      } catch (e) {
        debugPrint("Error loading saved header mapping: $e");
      }

      String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      for (var fieldKey in fieldOrder) {
        int? matchedIdx;

        if (savedHeaderMappings.containsKey(fieldKey)) {
          String savedHeader = savedHeaderMappings[fieldKey]?.toString() ?? "";
          String savedFmt = savedHeaderMappings["${fieldKey}__fmt"]?.toString() ?? "";
          int? savedIdx = int.tryParse(savedHeaderMappings["${fieldKey}__idx"]?.toString() ?? "");
          String savedCol = savedHeaderMappings["${fieldKey}__col"]?.toString() ?? "";

          String normSavedHeader = norm(savedHeader);
          String normSavedFmt = norm(savedFmt);

          if (savedIdx != null && savedIdx >= 0 && savedIdx < excelHeaders.length) {
            String currentH = excelHeaders[savedIdx];
            String currentLetter = ExcelWorkerService.getExcelColumnLetter(savedIdx);
            String currentFmt = "$currentH ($currentLetter)";
            if (norm(currentH) == normSavedHeader ||
                norm(currentFmt) == normSavedFmt ||
                currentLetter.toLowerCase() == savedCol.toLowerCase()) {
              matchedIdx = savedIdx;
            }
          }

          if (matchedIdx == null && normSavedFmt.isNotEmpty) {
            for (int i = 0; i < excelHeaders.length; i++) {
              String currentFmt = "${excelHeaders[i]} (${ExcelWorkerService.getExcelColumnLetter(i)})";
              if (norm(currentFmt) == normSavedFmt) {
                matchedIdx = i;
                break;
              }
            }
          }

          if (matchedIdx == null && normSavedHeader.isNotEmpty) {
            for (int i = 0; i < excelHeaders.length; i++) {
              if (norm(excelHeaders[i]) == normSavedHeader) {
                matchedIdx = i;
                break;
              }
            }
          }
        }

        if (matchedIdx == null) {
          String label = activeFields[fieldKey]!;
          List<String> keywords = [label];
          if (fieldKey == 'product' || fieldKey == 'name') {
            keywords.addAll(['name', 'product name', 'product', 'item name', 'item', 'particulars', 'description']);
          } else if (fieldKey == 'entry_no' || fieldKey == 'invoice_no') {
            keywords.addAll(['entry no', 'invoice no', 'inv no', 'bill no', 'entry', 'invoice']);
          } else if (fieldKey == 'inv_no') {
            keywords.addAll(['sup inv no', 'supplier inv no', 'invoice no', 'inv no', 'bill no']);
          } else if (fieldKey == 'inv_date' || fieldKey == 'date') {
            keywords.addAll(['date', 'inv date', 'bill date', 'entry date', 'purchase date', 'invoice date']);
          } else if (fieldKey == 'patient' || fieldKey == 'customer') {
            keywords.addAll(['patient', 'patient name', 'customer', 'customer name', 'party', 'patient_name']);
          } else if (fieldKey == 'doctor') {
            keywords.addAll(['doctor', 'dr', 'doctor name', 'dr name', 'prescribed by', 'doc']);
          } else if (fieldKey == 'mobile') {
            keywords.addAll(['mobile', 'mobile no', 'phone', 'contact', 'mobile number']);
          } else if (fieldKey == 'account') {
            keywords.addAll(['account', 'account type', 'payment type', 'payment mode', 'pay mode', 'mode']);
          } else if (fieldKey == 'agent') {
            keywords.addAll(['agent', 'sales agent', 'salesman', 'rep']);
          } else if (fieldKey == 'done_by') {
            keywords.addAll(['done by', 'user', 'created by', 'entered by']);
          } else if (fieldKey == 'supplier') {
            keywords.addAll(['supplier', 'vendor', 'party name', 'party']);
          } else if (fieldKey == 'qty' || fieldKey == 'stock') {
            keywords.addAll(['qty', 'quantity', 'billed qty', 'stock']);
          } else if (fieldKey == 'f_qty') {
            keywords.addAll(['f.qty', 'free qty', 'fqty', 'free']);
          } else if (fieldKey == 'p_rate' || fieldKey == 'l_cost') {
            keywords.addAll(['p.rate', 'prate', 'purchase rate', 'cost rate', 'cost', 'l.cost', 'lcost']);
          } else if (fieldKey == 'mrp') {
            keywords.addAll(['mrp', 'max price', 'mrp 1', 'mrp 2']);
          } else if (fieldKey == 'batch') {
            keywords.addAll(['batch', 'batch no', 'batch number']);
          } else if (fieldKey == 'expiry') {
            keywords.addAll(['expiry', 'exp date', 'exp', 'expiary']);
          } else if (fieldKey == 'packing') {
            keywords.addAll(['packing', 'pack', 'pck', 'packin']);
          } else if (fieldKey == 'total' || fieldKey == 'grand_total') {
            keywords.addAll(['total', 'grand total', 'net amount', 'amount', 'bill total', 'net']);
          } else if (fieldKey == 'disc_perc') {
            keywords.addAll(['disc %', 'discount %', 'disc percent', 'disc_perc', 'disc_per', 'disc_pct', 'dis_percent', 'dis_per']);
          } else if (fieldKey == 'disc_amt') {
            keywords.addAll(['disc amt', 'discount amt', 'disc val', 'disc amount', 'discount', 'disc', 'dis_amt']);
          } else if (fieldKey == 'gst_perc' || fieldKey == 'gst') {
            keywords.addAll(['gst %', 'tax %', 'gst rate', 'tax rate', 'gst percent', 'gst_perc', 'gst_per', 'tax_perc', 'tax_per']);
          } else if (fieldKey == 'gst_amt') {
            keywords.addAll(['gst_amt', 'gst amt', 'cgst_amt', 'sgst_amt', 'igst_amt', 'tax_amt', 'tax amount', 'gst', 'tax']);
          } else if (fieldKey == 'rack') {
            keywords.addAll(['rack', 'rackid', 'rack_id', 'location']);
          } else if (fieldKey == 'hsncode') {
            keywords.addAll(['hsncode', 'hsn', 'hsn code']);
          } else if (fieldKey == 'patent') {
            keywords.addAll(['patent', 'brand', 'company', 'category', 'patent name']);
          } else if (fieldKey == 'profit') {
            keywords.addAll(['profit', 'margin', 'net profit']);
          }

          for (var k in keywords) {
            String normK = norm(k);
            if (normK.isEmpty) continue;
            int idx = excelHeaders.indexWhere((h) => norm(h) == normK);
            if (idx != -1) {
              matchedIdx = idx;
              break;
            }
          }

          if (matchedIdx == null) {
            for (var k in keywords) {
              String normK = norm(k);
              if (normK.isEmpty) continue;
              int idx = excelHeaders.indexWhere((h) {
                String normH = norm(h);
                return normH.contains(normK) || normK.contains(normH);
              });
              if (idx != -1) {
                matchedIdx = idx;
                break;
              }
            }
          }
        }

        fieldMapping[fieldKey] = matchedIdx;
      }
    }

    await autoMapFields(rawHeaders);
    if (!mounted) return null;

    Set<String> errorFields = {};
    bool isMaximized = false;
    String? dialogErrorMessage;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          List<String> headers = rawHeaders;
          List<Map<String, dynamic>> fetched = List<Map<String, dynamic>>.from(currentAnalysis['fetched']);

          final screenSize = MediaQuery.of(context).size;
          final dialogWidth = isMaximized ? screenSize.width * 0.99 : screenSize.width * 0.94;
          final dialogHeight = isMaximized ? screenSize.height * 0.96 : screenSize.height * 0.90;

          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: DraggableModal(
              child: Dialog(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: SizedBox(
                  width: dialogWidth,
                  height: dialogHeight,
                  child: Column(
                    children: [
                      Container(
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Color(0xFF161E2E),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 16),
                            const Icon(Icons.analytics_rounded, color: Colors.blueAccent, size: 22),
                            const SizedBox(width: 10),
                            const Text("Intelligent Import Mapping", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            const Spacer(),
                            Text("${currentAnalysis['totalRows']} Rows detected", style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.bold)),
                            const SizedBox(width: 16),
                            _windowBtn(Icons.remove, () {
                              if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                            }),
                            _windowBtn(isMaximized ? Icons.filter_none : Icons.crop_square, () {
                              setDialogState(() => isMaximized = !isMaximized);
                            }),
                            _windowBtn(Icons.close, () {
                              if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                            }, isClose: true),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.blue.shade100)
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.lightbulb_outline_rounded, color: Colors.blue, size: 20),
                                    SizedBox(width: 12),
                                    Expanded(child: Text("ONE-TIME DATA MIGRATION: Simply match your Excel headers to the system fields below. IMPORTANT: 'Taxable Amount' is the value BEFORE GST. 'Grand Total' includes GST. If only one is available, the system will auto-calculate the other.", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.blueGrey))),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.grey.shade200),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
                                  ),
                                  child: _buildSystemFirstPreviewGrid(
                                    excelHeaders: headers,
                                    previewData: fetched,
                                    fieldOrder: fieldOrder,
                                    activeFields: activeFields,
                                    mapping: fieldMapping,
                                    errorFields: errorFields,
                                    isPurchase: isPurchase,
                                    isInventory: isInventory,
                                    isProductMaster: isProductMaster,
                                    onMap: (fieldKey, excelIdx) {
                                      setDialogState(() {
                                        fieldMapping[fieldKey] = excelIdx;
                                        errorFields.remove(fieldKey);
                                        if (dialogErrorMessage != null) dialogErrorMessage = null;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (dialogErrorMessage != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  dialogErrorMessage!,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              InkWell(
                                onTap: () => setDialogState(() => dialogErrorMessage = null),
                                child: const Padding(
                                  padding: EdgeInsets.all(4.0),
                                  child: Icon(Icons.close_rounded, color: Colors.white, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                          border: Border(top: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                              },
                              child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900)),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () {
                                List<String> missingFields = [];
                                Set<String> newErrors = {};

                                if (isInventory || isProductMaster) {
                                  if (fieldMapping['name'] == null && fieldMapping['product'] == null) {
                                    missingFields.add('Name / Product Name');
                                    newErrors.add('name');
                                    newErrors.add('product');
                                  }
                                } else {
                                  if (fieldMapping['product'] == null && fieldMapping['name'] == null) {
                                    missingFields.add('Product Name');
                                    newErrors.add('product');
                                  }
                                  if (fieldMapping['date'] == null) {
                                    missingFields.add('Date');
                                    newErrors.add('date');
                                  }
                                  if (fieldMapping['qty'] == null && fieldMapping['stock'] == null) {
                                    missingFields.add('Quantity');
                                    newErrors.add('qty');
                                  }
                                  if (isPurchase && fieldMapping['entry_no'] == null) {
                                    missingFields.add('Entry No');
                                    newErrors.add('entry_no');
                                  }
                                }

                                if (missingFields.isNotEmpty) {
                                  setDialogState(() {
                                    errorFields = newErrors;
                                    dialogErrorMessage = "MANDATORY MAPPINGS MISSING: Please map [ ${missingFields.join(', ')} ] before saving!";
                                  });
                                  return;
                                }

                                try {
                                  Map<String, dynamic> headerMapToPersist = {};
                                  fieldMapping.forEach((fKey, idx) {
                                    if (idx != null && idx >= 0 && idx < headers.length) {
                                      String headerText = headers[idx].trim();
                                      String colLetter = ExcelWorkerService.getExcelColumnLetter(idx);
                                      headerMapToPersist[fKey] = headerText;
                                      headerMapToPersist["${fKey}__col"] = colLetter;
                                      headerMapToPersist["${fKey}__idx"] = idx;
                                      headerMapToPersist["${fKey}__fmt"] = "$headerText ($colLetter)";
                                    }
                                  });
                                  String encoded = jsonEncode(headerMapToPersist);
                                  SharedPreferences.getInstance().then((prefs) {
                                    prefs.setString("excel_import_header_mapping_$importTypeKey", encoded);
                                    prefs.setString("excel_import_header_mapping_global", encoded);
                                  });
                                } catch (e) {
                                  debugPrint("Error saving import mapping: $e");
                                }

                                Map<String, int> finalMapping = {};
                                fieldMapping.forEach((k, v) {
                                  if (v != null && v >= 0 && v < headers.length) {
                                    String headerName = headers[v];
                                    int rawIdx = rawHeaders.indexOf(headerName);
                                    if (rawIdx != -1) {
                                      finalMapping[k] = rawIdx;
                                    } else {
                                      finalMapping[k] = v;
                                    }
                                  }
                                });
                                if (Navigator.canPop(ctx)) {
                                  Navigator.pop(ctx, finalMapping.isEmpty ? true : finalMapping);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 2,
                              ),
                              child: const Text("SAVE & UPLOAD EVERYTHING", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _windowBtn(IconData icon, VoidCallback onTap, {bool isClose = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: isClose ? Colors.red : Colors.white24,
        child: Container(
          width: 40,
          height: 44,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }

  String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Widget _buildSystemFirstPreviewGrid({
    required List<String> excelHeaders,
    required List<Map<String, dynamic>> previewData,
    required List<String> fieldOrder,
    required Map<String, String> activeFields,
    required Map<String, int?> mapping,
    required Set<String> errorFields,
    bool isPurchase = false,
    bool isInventory = false,
    bool isProductMaster = false,
    required Function(String, int?) onMap,
  }) {
    final ScrollController horizCtrl = ScrollController();
    final ScrollController vertCtrl = ScrollController();

    return Scrollbar(
      controller: horizCtrl,
      thumbVisibility: true,
      trackVisibility: true,
      thickness: 10,
      radius: const Radius.circular(5),
      child: SingleChildScrollView(
        controller: horizCtrl,
        scrollDirection: Axis.horizontal,
        child: Scrollbar(
          controller: vertCtrl,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8,
          radius: const Radius.circular(4),
          child: SingleChildScrollView(
            controller: vertCtrl,
            scrollDirection: Axis.vertical,
            child: DataTable(
              headingRowHeight: 110,
              headingRowColor: WidgetStateProperty.all(Colors.blueGrey.shade50.withValues(alpha: 0.5)),
              columnSpacing: 20,
              columns: fieldOrder.map((fieldKey) {
                String label = activeFields[fieldKey]!;
                int? mappedIdx = mapping[fieldKey];

                bool isMandatory = (isInventory || isProductMaster)
                    ? (fieldKey == 'name' || fieldKey == 'product')
                    : (isPurchase
                    ? ['product', 'name', 'date', 'qty', 'entry_no'].contains(fieldKey)
                    : ['product', 'name', 'date', 'qty'].contains(fieldKey));
                bool isError = errorFields.contains(fieldKey) || (isMandatory && mappedIdx == null && errorFields.isNotEmpty);

                return DataColumn(
                  label: Container(
                    width: 190,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                label.toUpperCase(),
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 10,
                                    color: isError ? Colors.red.shade800 : Colors.blueGrey.shade700,
                                    letterSpacing: 0.5
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isMandatory) const Text(" *", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 38,
                          child: _EditableHeaderDropdown(
                            key: ValueKey("editable_${fieldKey}_${excelHeaders.length}_$mappedIdx"),
                            rawHeaders: excelHeaders,
                            mappedIdx: mappedIdx,
                            isError: isError,
                            onMap: (int? newIdx) => onMap(fieldKey, newIdx),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              rows: previewData.map((row) {
                return DataRow(
                  cells: fieldOrder.map((fieldKey) {
                    int? idx = mapping[fieldKey];
                    String value = "";
                    if (idx != null && idx >= 0 && idx < excelHeaders.length) {
                      String excelHeader = excelHeaders[idx];

                      value = row[excelHeader]?.toString() ?? "";

                      if (value.trim().isEmpty) {
                        String normHeader = _norm(excelHeader);
                        for (var entry in row.entries) {
                          if (_norm(entry.key) == normHeader) {
                            value = entry.value?.toString() ?? "";
                            break;
                          }
                        }
                      }

                      if (value.trim().isEmpty) {
                        String rawColName = excelHeader;
                        if (excelHeader.contains(" — ")) {
                          rawColName = excelHeader.split(" — ").last.trim();
                          if (rawColName.contains(" (")) {
                            rawColName = rawColName.substring(0, rawColName.lastIndexOf(" (")).trim();
                          }
                        }
                        value = row[rawColName]?.toString() ?? "";
                      }

                      if (value.trim().isEmpty && idx < row.values.length) {
                        value = row.values.elementAt(idx)?.toString() ?? "";
                      }
                    }

                    value = value.trim();
                    if (value.isEmpty) value = "-";

                    if (value != "-" && ['date', 'inv_date', 'expiry'].contains(fieldKey) && value.isNotEmpty) {
                      double? d = double.tryParse(value);
                      if (d != null && d > 1000) {
                        try {
                          DateTime dt = DateTime(1899, 12, 30).add(Duration(days: d.toInt()));
                          value = DateFormat(fieldKey == 'expiry' ? 'MM/yy' : 'dd/MM/yy').format(dt);
                        } catch (_) {}
                      } else if (value.contains('T') && DateTime.tryParse(value) != null) {
                        try {
                          DateTime dt = DateTime.parse(value);
                          value = DateFormat(fieldKey == 'expiry' ? 'MM/yy' : 'dd/MM/yy').format(dt);
                        } catch (_) {}
                      }
                    }

                    if (value != "-" && ['gst', 'gst_perc', 'gst_percent', 'taxper', 'tax_per', 'cgst', 'sgst'].contains(fieldKey.toLowerCase()) && value.isNotEmpty) {
                      double? d = double.tryParse(value);
                      if (d != null) {
                        double rounded = TaxCalculator.roundGstPercent(d);
                        value = rounded % 1 == 0 ? rounded.toInt().toString() : rounded.toStringAsFixed(1);
                      }
                    }

                    return DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          value,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: idx != null ? Colors.black87 : Colors.grey.shade300
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  void _showPasswordDialog(PharmacyProvider provider) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(provider.masterPassword.isEmpty ? "Create PIN" : "Reset PIN", style: AppStyles.h2),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(hintText: "Enter 4-6 digit PIN", border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                provider.setMasterPassword(ctrl.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text("SAVE PIN"),
          )
        ],
      ),
    );
  }

  Widget _buildPrintSettings() {
    return const SizedBox(
      height: 800,
      child: PrinterCustomizationScreen(useScaffold: false),
    );
  }

  Widget _buildSectionHeader(String title, String sub) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppStyles.h2Of(context)),
        const SizedBox(height: 4),
        Text(sub, style: TextStyle(color: c.secondaryText, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildInputCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: AppStyles.cardDecorationOf(context),
      child: Column(children: children),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctrl, {int maxLines = 1, bool isCyan = false}) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppStyles.labelOf(context).copyWith(fontSize: 10)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isCyan ? const Color(0xFF0284C7).withValues(alpha: 0.15) : c.inputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: TextField(
            controller: ctrl,
            maxLines: maxLines,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: c.primaryText),
            decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(16)),
          ),
        ),
      ],
    );
  }

  void _showProgressDialog(String message, Stream<double> progressStream) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            Provider.of<PharmacyProvider>(context, listen: false).cancelImport();
            if (Navigator.canPop(ctx)) Navigator.pop(ctx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: StreamBuilder<double>(
          stream: progressStream,
          initialData: 0.0,
          builder: (context, snapshot) {
            double progress = snapshot.data ?? 0.0;
            return Center(
              child: Container(
                width: 300,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 24),
                    LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                    const SizedBox(height: 12),
                    Text("${(progress * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.blueGrey)),
                    const SizedBox(height: 24),
                    TextButton.icon(
                      onPressed: () {
                        Provider.of<PharmacyProvider>(context, listen: false).cancelImport();
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                      label: const Text("CANCEL", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? Colors.red : Colors.green,
        content: Text(msg),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _saveSettings() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final updatedProfile = CompanyProfile(
      name: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      gstIn: _gstCtrl.text.trim(),
      dlNumber: provider.companyProfile.dlNumber,
      tagline: provider.companyProfile.tagline,
    );
    await provider.saveCompanyProfile(updatedProfile);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('github_repo_path', _githubRepoCtrl.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.green, content: Text("Store settings and branding saved successfully!")),
      );
    }
  }

  Widget _buildDatabaseResetSettings(BuildContext context, PharmacyProvider provider) {
    final c = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          "Selective Database Reset & Remote Wipe",
          "Tick the items you want to delete from Local PC and Cloud Server. Unchecked items remain completely safe.",
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.isDark ? const Color(0xFF451A03) : const Color(0xFFFFF1F2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.shade300, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "PERMANENT DATA WIPE WARNING",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Colors.red.shade900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Ticked categories will be permanently erased from BOTH this Local Computer and Supabase Cloud. Unchecked categories will NOT be deleted.",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade800,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.redAccent),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "${_selectedResetCategoryIds.length} of 14 Items Selected",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedResetCategoryIds = {
                              'batches',
                              'sales',
                              'purchases',
                              'sales_returns',
                              'purchase_returns',
                              'prescriptions_adjustments',
                              'damages',
                              'customer_account',
                              'wholesale_account',
                              'accounts_daybook',
                              'vouchers',
                            };
                          });
                        },
                        icon: const Icon(Icons.cleaning_services_rounded, size: 16, color: Colors.orange),
                        label: const Text('Keep Product Master Only', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange)),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedResetCategoryIds = {
                              'products',
                              'batches',
                              'sales',
                              'purchases',
                              'sales_returns',
                              'purchase_returns',
                              'prescriptions_adjustments',
                              'damages',
                              'patients',
                              'suppliers_doctors',
                              'customer_account',
                              'wholesale_account',
                              'accounts_daybook',
                              'vouchers',
                            };
                          });
                        },
                        icon: const Icon(Icons.select_all_rounded, size: 16, color: Colors.red),
                        label: const Text('Select All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red)),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedResetCategoryIds.clear();
                          });
                        },
                        icon: const Icon(Icons.deselect_rounded, size: 16, color: Colors.grey),
                        label: const Text('Deselect All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildResetSelectionSection("STOCK", Colors.blue, [
                {'id': 'products', 'title': 'Registered Stocks', 'subtitle': 'Product catalog, prices, categories & schedules', 'icon': Icons.medication_rounded},
                {'id': 'batches', 'title': 'Inventory', 'subtitle': 'Batch stock, expiry dates, quantities & rates', 'icon': Icons.layers_rounded},
              ], c),
              const SizedBox(height: 16),
              _buildResetSelectionSection("TRANSACTION", Colors.orange, [
                {'id': 'sales', 'title': 'Sales', 'subtitle': 'Sales invoices & counter bills', 'icon': Icons.point_of_sale_rounded},
                {'id': 'purchases', 'title': 'Purchase', 'subtitle': 'Purchase inward entries & supplier bills', 'icon': Icons.shopping_bag_rounded},
                {'id': 'sales_returns', 'title': 'Sales Return', 'subtitle': 'Customer credit notes & return receipts', 'icon': Icons.assignment_return_rounded},
                {'id': 'purchase_returns', 'title': 'Purchase Return', 'subtitle': 'Supplier debit notes & outward returns', 'icon': Icons.unarchive_rounded},
                {'id': 'prescriptions_adjustments', 'title': 'Adjustment', 'subtitle': 'Stock adjustments & opening adjustments', 'icon': Icons.tune_rounded},
                {'id': 'damages', 'title': 'Damage', 'subtitle': 'Stock write-offs & damage entries', 'icon': Icons.remove_shopping_cart_rounded},
              ], c),
              const SizedBox(height: 16),
              _buildResetSelectionSection("ACCOUNTS & CONTACTS", Colors.green, [
                {'id': 'patients', 'title': 'Patients, Doctors & Phone Numbers', 'subtitle': 'Patient contacts, prescribing doctors & phone registry', 'icon': Icons.people_alt_rounded},
                {'id': 'suppliers_doctors', 'title': 'Suppliers & Wholesalers', 'subtitle': 'Distributor masters, GSTIN & drug license numbers', 'icon': Icons.medical_services_rounded},
              ], c),
              const SizedBox(height: 16),
              _buildResetSelectionSection("LEDGER & VOUCHERS", Colors.purple, [
                {'id': 'customer_account', 'title': 'Customer Account', 'subtitle': 'Customer credit ledger & receivables', 'icon': Icons.person_search_rounded},
                {'id': 'wholesale_account', 'title': 'Wholesale Account', 'subtitle': 'Wholesaler payable ledger', 'icon': Icons.store_rounded},
                {'id': 'accounts_daybook', 'title': 'Daybook, Shop Expenses & Petty Cash', 'subtitle': 'Daily cash, expenses & petty cash register', 'icon': Icons.today_rounded},
                {'id': 'vouchers', 'title': 'Vouchers', 'subtitle': 'Payment & receipt cash vouchers', 'icon': Icons.receipt_rounded},
              ], c),
              const SizedBox(height: 24),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _selectedResetCategoryIds.isEmpty ? null : () => _confirmAndExecuteFullWipe(context, provider),
                    icon: const Icon(Icons.delete_forever_rounded, size: 22),
                    label: Text(
                      "🚨 PERMANENTLY RESET SELECTED DATA (${_selectedResetCategoryIds.length} ITEMS SELECTED)",
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade400,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResetSelectionSection(String sectionTitle, MaterialColor sectionColor, List<Map<String, dynamic>> items, AppThemeColors c) {
    final secItemIds = items.map((i) => i['id'] as String).toSet();
    final isSecAllSelected = secItemIds.every((id) => _selectedResetCategoryIds.contains(id));

    return Container(
      decoration: BoxDecoration(
        color: c.isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sectionColor.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(color: sectionColor, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    sectionTitle,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: sectionColor.shade800, letterSpacing: 0.5),
                  ),
                ],
              ),
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 24)),
                onPressed: () {
                  setState(() {
                    if (isSecAllSelected) {
                      _selectedResetCategoryIds.removeAll(secItemIds);
                    } else {
                      _selectedResetCategoryIds.addAll(secItemIds);
                    }
                  });
                },
                child: Text(
                  isSecAllSelected ? "Deselect Section" : "Select Section",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sectionColor.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: items.map((item) {
              final String id = item['id'] as String;
              final String title = item['title'] as String;
              final String subtitle = item['subtitle'] as String;
              final IconData icon = item['icon'] as IconData;
              final bool isSelected = _selectedResetCategoryIds.contains(id);

              return InkWell(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedResetCategoryIds.remove(id);
                    } else {
                      _selectedResetCategoryIds.add(id);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 380,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (c.isDark ? sectionColor.shade900.withValues(alpha: 0.3) : sectionColor.shade50)
                        : (c.isDark ? const Color(0xFF1E293B) : Colors.grey.shade50),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? sectionColor.shade400 : Colors.grey.shade300,
                      width: isSelected ? 1.8 : 1.0,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: isSelected,
                        activeColor: sectionColor.shade700,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedResetCategoryIds.add(id);
                            } else {
                              _selectedResetCategoryIds.remove(id);
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      Icon(icon, color: isSelected ? sectionColor.shade700 : Colors.grey.shade600, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isSelected ? sectionColor.shade900 : Colors.black87)),
                            const SizedBox(height: 2),
                            Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndExecuteFullWipe(BuildContext context, PharmacyProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text('Confirm Full System Reset', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Are you 100% sure you want to permanently erase ALL sales, inventory, products, and purchase records from this computer and the cloud server?\n\nThis action cannot be undone!',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('YES, ERASE EVERYTHING'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final progressNotifier = ValueNotifier<double>(0.0);
      final statusNotifier = ValueNotifier<String>('Starting Full Database Reset...');

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.red)),
                const SizedBox(height: 16),
                const Text('Full System Reset in Progress...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 12),
                ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (context, statusText, _) => Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (context, progress, _) {
                    int pctInt = (progress.clamp(0.0, 1.0) * 100).toInt();
                    return Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            minHeight: 10,
                            color: Colors.red.shade700,
                            backgroundColor: Colors.red.shade100,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('$pctInt%', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.red.shade900, fontSize: 14)),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );

      final Map<String, dynamic> result = await provider.performFullSystemWipe(
        selectedCategories: _selectedResetCategoryIds,
        onProgress: (pct, msg) {
          progressNotifier.value = pct;
          statusNotifier.value = msg;
        },
      );

      if (context.mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      if (context.mounted) {
        final bool isSuccess = result['success'] == true;
        final int cloudSuccess = result['cloudSuccessCount'] as int? ?? 0;
        final int cloudTotal = result['cloudTotalCount'] as int? ?? 13;
        final bool localSuccess = result['localSuccess'] == true;
        final List failedList = (result['failedEndpoints'] as List?) ?? [];

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(
                  isSuccess ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                  color: isSuccess ? Colors.green : Colors.orange.shade800,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  isSuccess ? 'Full Reset Completed (100%)' : 'Reset Finished with Warnings',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSuccess ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSuccess ? Colors.green.shade300 : Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(isSuccess ? Icons.task_alt_rounded : Icons.info_outline, color: isSuccess ? Colors.green.shade800 : Colors.orange.shade900, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isSuccess
                                ? 'All local SQLite tables and Supabase cloud tables reset to 0.'
                                : 'Local database reset successfully. Some cloud endpoints requires attention.',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSuccess ? Colors.green.shade900 : Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('RESET BREAKDOWN REPORT:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.blueGrey)),
                  const SizedBox(height: 8),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(localSuccess ? Icons.check_circle : Icons.cancel, color: localSuccess ? Colors.green : Colors.red, size: 20),
                    title: const Text('Local SQLite Database', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(localSuccess ? 'All local tables cleared to 0 rows' : 'Local wipe failed', style: const TextStyle(fontSize: 11)),
                  ),
                  const Divider(height: 8),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(cloudSuccess == cloudTotal ? Icons.check_circle : Icons.warning_rounded, color: cloudSuccess == cloudTotal ? Colors.green : Colors.orange, size: 20),
                    title: const Text('Supabase Cloud REST Tables', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text('$cloudSuccess / $cloudTotal Cloud Tables Wiped Successfully', style: const TextStyle(fontSize: 11)),
                  ),
                  if (failedList.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Text('Failed Cloud Endpoints: ${failedList.join(', ')}', style: TextStyle(fontSize: 11, color: Colors.red.shade900, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: isSuccess ? Colors.green.shade800 : Colors.blue.shade800, foregroundColor: Colors.white),
                onPressed: () {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: const Text('OK, CLOSE'),
              ),
            ],
          ),
        );
      }
    }
  }

  Widget _actionBtn(String label, IconData icon, Color color, {VoidCallback? onTap}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 8,
          shadowColor: color.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

class _EditableHeaderDropdown extends StatefulWidget {
  final List<String> rawHeaders;
  final int? mappedIdx;
  final bool isError;
  final Function(int?) onMap;

  const _EditableHeaderDropdown({
    super.key,
    required this.rawHeaders,
    required this.mappedIdx,
    required this.isError,
    required this.onMap,
  });

  @override
  State<_EditableHeaderDropdown> createState() => _EditableHeaderDropdownState();
}

class _EditableHeaderDropdownState extends State<_EditableHeaderDropdown> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();

  String _formatOption(int idx) {
    if (idx < 0 || idx >= widget.rawHeaders.length) return "Skip Column";
    String colLetter = ExcelWorkerService.getExcelColumnLetter(idx);
    String hName = widget.rawHeaders[idx].trim();
    if (hName.isEmpty) {
      return "Column $colLetter ($colLetter)";
    }
    return "$hName ($colLetter)";
  }

  @override
  void initState() {
    super.initState();
    String initText = (widget.mappedIdx != null && widget.mappedIdx! >= 0 && widget.mappedIdx! < widget.rawHeaders.length)
        ? _formatOption(widget.mappedIdx!)
        : (widget.isError ? "CHOOSE COLUMN" : "Skip Column");
    _ctrl = TextEditingController(text: initText);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _EditableHeaderDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    String targetText = (widget.mappedIdx != null && widget.mappedIdx! >= 0 && widget.mappedIdx! < widget.rawHeaders.length)
        ? _formatOption(widget.mappedIdx!)
        : (widget.isError ? "CHOOSE COLUMN" : "Skip Column");
    if (!_focusNode.hasFocus && _ctrl.text != targetText) {
      _ctrl.text = targetText;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _resolveSelection();
    }
  }

  int? _resolveIndex(String text) {
    String cleanT = text.trim().toLowerCase();
    if (cleanT.isEmpty || cleanT == "skip column" || cleanT == "choose column") return null;

    for (int i = 0; i < widget.rawHeaders.length; i++) {
      String hName = widget.rawHeaders[i].trim().toLowerCase();
      String colLetter = ExcelWorkerService.getExcelColumnLetter(i).toLowerCase();
      String singleLetter = colLetter.split(":").first;
      String formattedOption = _formatOption(i).toLowerCase();

      if (cleanT == hName ||
          cleanT == formattedOption ||
          cleanT == colLetter ||
          cleanT == singleLetter) {
        return i;
      }
    }

    for (int i = 0; i < widget.rawHeaders.length; i++) {
      String hName = widget.rawHeaders[i].trim().toLowerCase();
      if (hName.isNotEmpty && hName.startsWith(cleanT)) {
        return i;
      }
    }

    for (int i = 0; i < widget.rawHeaders.length; i++) {
      String hName = widget.rawHeaders[i].trim().toLowerCase();
      if (hName.isNotEmpty && (hName.contains(cleanT) || cleanT.contains(hName))) {
        return i;
      }
    }

    return null;
  }

  void _resolveSelection() {
    String text = _ctrl.text.trim();
    int? idx = _resolveIndex(text);
    if (idx != null) {
      _ctrl.text = _formatOption(idx);
      widget.onMap(idx);
    } else {
      _ctrl.text = widget.isError ? "CHOOSE COLUMN" : "Skip Column";
      widget.onMap(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<String> allOptions = ["Skip Column"];
    for (int i = 0; i < widget.rawHeaders.length; i++) {
      allOptions.add(_formatOption(i));
    }

    return RawAutocomplete<String>(
      textEditingController: _ctrl,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        String search = textEditingValue.text.trim().toLowerCase();
        String currentSelection = (widget.mappedIdx != null && widget.mappedIdx! >= 0 && widget.mappedIdx! < widget.rawHeaders.length)
            ? _formatOption(widget.mappedIdx!).toLowerCase()
            : (widget.isError ? "choose column" : "skip column");

        if (search.isEmpty || search == currentSelection) {
          return allOptions;
        }

        final startsWithMatches = allOptions.where((o) {
          if (o == "Skip Column") return false;
          return o.toLowerCase().startsWith(search);
        }).toList();

        final containsMatches = allOptions.where((o) {
          if (o == "Skip Column") return false;
          return !o.toLowerCase().startsWith(search) && o.toLowerCase().contains(search);
        }).toList();

        return [
          if ("skip column".contains(search)) "Skip Column",
          ...startsWithMatches,
          ...containsMatches,
        ];
      },
      onSelected: (String selection) {
        if (selection == "Skip Column") {
          _ctrl.text = widget.isError ? "CHOOSE COLUMN" : "Skip Column";
          widget.onMap(null);
        } else {
          int? idx = _resolveIndex(selection);
          if (idx != null) {
            _ctrl.text = _formatOption(idx);
            widget.onMap(idx);
          }
        }
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onTap: () {
            controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
          },
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: widget.mappedIdx != null
                ? Colors.blue.shade900
                : (widget.isError ? Colors.red.shade900 : Colors.black87),
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            filled: true,
            fillColor: widget.mappedIdx != null
                ? Colors.blue.shade50
                : (widget.isError ? Colors.red.shade50 : Colors.grey.shade100),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: widget.mappedIdx != null
                    ? Colors.blue.shade300
                    : (widget.isError ? Colors.red : Colors.grey.shade300),
                width: widget.isError ? 2 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: widget.isError ? Colors.red : Colors.blue.shade600,
                width: 2,
              ),
            ),
            suffixIcon: Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: widget.mappedIdx != null ? Colors.blue.shade700 : (widget.isError ? Colors.red : Colors.grey.shade600),
            ),
          ),
          onSubmitted: (_) {
            _resolveSelection();
            onFieldSubmitted();
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8.0,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 260,
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.blueGrey.shade50,
                    width: double.infinity,
                    child: const Text(
                      "CHOOSE EXCEL COLUMN:",
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.blueGrey),
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                      itemBuilder: (context, index) {
                        final String option = options.elementAt(index);
                        final bool isSkip = option == "Skip Column";
                        return InkWell(
                          onTap: () => onSelected(option),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            color: isSkip ? Colors.red.shade50.withValues(alpha: 0.3) : null,
                            child: Row(
                              children: [
                                Icon(
                                  isSkip ? Icons.block_flipped : Icons.view_column_rounded,
                                  size: 14,
                                  color: isSkip ? Colors.red : Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    option,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isSkip ? Colors.red.shade900 : Colors.black87,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}