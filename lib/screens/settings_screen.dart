import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/theme_constants.dart';
import '../utils/app_dialogs.dart';
import '../utils/tax_calculator.dart';
import '../widgets/draggable_modal.dart';
import 'printer_customization_screen.dart';
import 'edited_invoices_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String? initialTab;
  const SettingsScreen({super.key, this.initialTab});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _currentAppVersion = "2.4.0";
  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _gstCtrl;
  late TextEditingController _githubRepoCtrl;
  late TextEditingController _githubTokenCtrl;
  String _activeTab = "Pharmacy Profile";
  String? _salesFy = "All Years";
  String? _purchaseFy = "All Years";
  String? _salesReturnFy = "All Years";
  String? _purchaseReturnFy = "All Years";
  String? _damageFy = "All Years";

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null) {
      _activeTab = widget.initialTab!;
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
    if (mounted) {
      setState(() {
        if (savedRepo != null && savedRepo.isNotEmpty) {
          _githubRepoCtrl.text = savedRepo;
        }
        if (savedToken != null && savedToken.isNotEmpty) {
          _githubTokenCtrl.text = savedToken;
        }
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
            child: _activeTab == "Edited Invoices"
                ? Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_activeTab.toUpperCase(), style: AppStyles.labelOf(context).copyWith(fontSize: 12, letterSpacing: 2)),
                        const SizedBox(height: 32),
                        const Expanded(child: EditedInvoicesScreen(headless: true)),
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
                        if (_activeTab == "Security & Backup") _buildDataSettings(),
                        if (_activeTab == "Print Customization") _buildPrintSettings(),
                        if (_activeTab == "Fiscal Calendar") _buildFiscalCalendarSettings(provider),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
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
          const SizedBox(height: 48),
          _settingsTab("Pharmacy Profile", Icons.store_rounded),
          _settingsTab("Fiscal Calendar", Icons.calendar_month_rounded),
          _settingsTab("Security & Backup", Icons.admin_panel_settings_rounded),
          _settingsTab("Edited Invoices", Icons.history_rounded),
          _settingsTab("Print Customization", Icons.print_rounded),
          _settingsTab("User Accounts", Icons.people_alt_rounded),
          const Spacer(),
          _actionBtn("SAVE ALL CHANGES", Icons.check_circle_rounded, AppColors.success, onTap: _saveSettings),
        ],
      ),
    );
  }

  Widget _settingsTab(String label, IconData icon) {
    bool isActive = _activeTab == label;
    return InkWell(
      onTap: () => setState(() => _activeTab = label),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))] : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isActive ? AppColors.secondary : Colors.blueGrey.shade300),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w900 : FontWeight.w600, color: isActive ? AppColors.primary : Colors.blueGrey.shade600)),
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
        
        // Card 1: Software Opening Date Config
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
                        const Text(
                          "Software Opening Date",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
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

        // Card 2: Current Active Financial Year & Year List
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
                                Text(
                                  dateRangeStr,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                ),
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.system_update_rounded, color: Colors.blue, size: 28),
                  ),
                  const SizedBox(width: 20),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Sahakar Medicals ERP", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        SizedBox(height: 4),
                        Text("Version $_currentAppVersion (Commercial Build • Stable)", style: TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
                      ],
                    ),
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
                  Row(
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
                  const SizedBox(height: 12),
                  Row(
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
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("GitHub repository and access token credentials saved successfully!"),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                    ],
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text("Checking GitHub Releases ($repoPath)...", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ),
      ),
    );

    try {
      final client = HttpClient();
      final url = Uri.parse('https://api.github.com/repos/$repoPath/releases/latest');
      final request = await client.getUrl(url);
      request.headers.set('User-Agent', 'PharmacyERP-Updater');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close().timeout(const Duration(seconds: 10));

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final Map<String, dynamic> releaseData = jsonDecode(responseBody);

        final String tagName = releaseData['tag_name'] ?? '';
        final String releaseName = releaseData['name'] ?? tagName;
        final String htmlUrl = releaseData['html_url'] ?? '';
        final String body = releaseData['body'] ?? 'No release notes provided.';
        final String publishedAt = releaseData['published_at'] ?? '';

        if (_isVersionNewer(tagName, _currentAppVersion)) {
          _showUpdateAvailableDialog(
            latestVersion: tagName,
            releaseName: releaseName,
            htmlUrl: htmlUrl,
            body: body,
            publishedAt: publishedAt,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Software is fully up to date! (Current version: v$_currentAppVersion)"),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (response.statusCode == 404) {
        _showUpdateErrorDialog(
          "GitHub Release Not Found",
          "No published releases were found for repository '$repoPath'.\n\n"
          "Please verify:\n"
          "1. The GitHub repository is set to Public.\n"
          "2. You have created and published at least one Release on GitHub.",
        );
      } else {
        _showUpdateErrorDialog(
          "GitHub API Error",
          "GitHub returned status code ${response.statusCode}.\n"
          "Please verify your repository path and try again later.",
        );
      }
      client.close();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      _showUpdateErrorDialog(
        "Connection Error",
        "Unable to connect to GitHub Releases API.\n\n"
        "Error details: ${e.toString().replaceAll('Exception: ', '')}\n\n"
        "Please check your internet connection.",
      );
    }
  }

  bool _isVersionNewer(String latestTag, String currentVersion) {
    String clean(String v) => v.replaceAll(RegExp(r'^[vV]'), '').split('-').first.trim();
    final latestParts = clean(latestTag).split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts = clean(currentVersion).split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  void _showUpdateAvailableDialog({
    required String latestVersion,
    required String releaseName,
    required String htmlUrl,
    required String body,
    required String publishedAt,
  }) {
    String formattedDate = publishedAt;
    try {
      if (publishedAt.isNotEmpty) {
        final dt = DateTime.parse(publishedAt);
        formattedDate = DateFormat('MMM dd, yyyy').format(dt);
      }
    } catch (_) {}

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.system_update_rounded, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text("New Update Available!", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Current: v$_currentAppVersion", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey)),
                        const SizedBox(height: 4),
                        Text("Latest: $latestVersion", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue.shade900)),
                      ],
                    ),
                    const Spacer(),
                    if (formattedDate.isNotEmpty)
                      Chip(
                        avatar: const Icon(Icons.calendar_today_rounded, size: 14),
                        label: Text(formattedDate, style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(releaseName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              const Text("RELEASE NOTES:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    body.isEmpty ? "No release details provided." : body,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("LATER", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              if (htmlUrl.isNotEmpty) {
                _openUrl(htmlUrl);
              }
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text("DOWNLOAD UPDATE", style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  void _showUpdateErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (e) {
      debugPrint("Error launching URL: $e");
    }
  }

  Widget _buildDataSettings() {
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
                      onPressed: () => _showPasswordDialog(provider),
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
        _buildSectionHeader("Database Management", "Ensure your data is safe and synchronized."),
        const SizedBox(height: 32),
        Wrap(
          spacing: 24,
          runSpacing: 16,
          children: [
            _dbActionTile(
              "Local Backup", 
              "Create instant .db snapshot", 
              Icons.cloud_upload_rounded, 
              Colors.teal,
              onTap: () => _performBackup(provider),
            ),
            _dbActionTile(
              "Restore Hub", 
              "Rollback to 30-day backups", 
              Icons.history_rounded, 
              Colors.orange.shade800,
              onTap: () => _showRestoreHubDialog(provider),
            ),
            _dbActionTile(
              "Import External .db File", 
              "Restore from Pendrive / USB", 
              Icons.file_open_rounded, 
              Colors.indigo,
              onTap: () => _importExternalDbBackup(provider),
            ),
          ],
        ),
        const SizedBox(height: 48),
        _buildExportSection(provider),
        const SizedBox(height: 48),
        _buildImportSection(provider),
        const SizedBox(height: 48),
        _buildDbStats(provider),
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDbStats(PharmacyProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Database Diagnostics", "Real-time summary of records currently stored in your software."),
        const SizedBox(height: 24),
        Container(
          width: 624,
          padding: const EdgeInsets.all(24),
          decoration: AppStyles.cardDecorationOf(context),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem("Total Sales", provider.sales.length.toString(), Colors.blue),
              _statItem("Purchases", provider.purchases.length.toString(), Colors.indigo),
              _statItem("Products", provider.productMaster.length.toString(), Colors.teal),
              _statItem("Patients", provider.patients.length.toString(), Colors.orange),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          "Tip: If records aren't showing in History screens, check your Date Filters. Imported records will appear under their original dates.",
          style: TextStyle(fontSize: 12, color: Colors.blueGrey, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
      ],
    );
  }

  Widget _buildImportSection(PharmacyProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Legacy CSV Data Import", "Quick import for basic inventory and sales from older spreadsheets."),
        const SizedBox(height: 24),
        Row(
          children: [
            _dbActionTile(
              "Import Sales History",
              "Upload past sales excel/csv records",
              Icons.cloud_download_rounded,
              Colors.teal,
              btnLabel: "IMPORT",
              onTap: () async {
                FilePickerResult? result = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['xlsx', 'xls', 'csv'],
                );

                if (result != null && result.files.single.path != null) {
                  String filePath = result.files.single.path!;
                  if (!mounted) return;

                  final controller = StreamController<double>();
                  _showProgressDialog("Importing Sales History...", controller.stream);

                  Map<String, dynamic> res = await provider.importSalesFromExcel(
                    filePath,
                    onProgress: (p, statusText) {
                      if (!controller.isClosed) controller.add(p);
                    },
                  );

                  if (!mounted) return;
                  Navigator.pop(context); // Close progress dialog
                  controller.close();

                  if (res['success'] == true) {
                    await provider.loadFromDatabase();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.green,
                        content: Text("Successfully imported ${res['invoices']} invoices (${res['items']} items) in seconds!"),
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.red,
                        content: Text(res['message'] ?? "Import failed."),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExportSection(PharmacyProvider provider) {
    List<String> availableFys = provider.availableFinancialYears;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Excel Data Synchronization", "Transfer detailed records between systems with real-time tracking."),
        const SizedBox(height: 16),
        _buildBackgroundSyncMonitor(provider),
        const SizedBox(height: 8),
        // SET 1: Master Catalog & Current Inventory
        Row(
          children: [
            _dbActionTile(
              "Product Master",
              "Master catalog and product items",
              Icons.medication_rounded,
              Colors.purple.shade700,
              btnLabel: "EXPORT",
              headings: ["Name", "Packing", "RACK", "hsncode", "MRP", "P.RATE", "Patent", "Generic Name", "Gst", "Category", "Sub Category", "Sdisc%", "Schedule"],
              selectedFy: null,
              availableFys: null,
              onFyChanged: null,
              onTap: () => _handleSync(
                title: "Export Product Master",
                action: (p, path, progress, fy) => p.exportProductMasterToExcel(path, onProgress: progress),
                isExport: true,
                provider: provider,
                financialYear: null,
              ),
              importTap: () => _handleSync(
                title: "Import Product Master",
                action: (p, path, progress, fy) => p.importProductMasterFromExcel(path, onProgress: progress),
                isExport: false,
                provider: provider,
                financialYear: null,
              ),
              deleteTap: () => _handleDelete(
                title: "Product Master",
                deleteAction: (p, fy) => p.deleteProductMasterRecords(),
                provider: provider,
                financialYear: null,
              ),
            ),
            const SizedBox(width: 24),
            _dbActionTile(
              "Inventory",
              "Current stock and batch records",
              Icons.inventory_2_rounded,
              Colors.teal.shade700,
              btnLabel: "EXPORT",
              headings: ["Name", "Packing", "Stock", "Batch", "Expiry", "MRP", "L Cost", "MRP Value", "Supplier", "Gst%", "Category", "Sub Category"],
              selectedFy: null,
              availableFys: null,
              onFyChanged: null,
              onTap: () => _handleSync(
                title: "Export Inventory",
                action: (p, path, progress, fy) => p.exportInventoryToExcel(path, onProgress: progress),
                isExport: true,
                provider: provider,
                financialYear: null,
              ),
              importTap: () => _handleSync(
                title: "Import Inventory",
                action: (p, path, progress, fy) => p.importInventoryFromExcel(path, onProgress: progress),
                isExport: false,
                provider: provider,
                financialYear: null,
              ),
              deleteTap: () => _handleDelete(
                title: "Inventory",
                deleteAction: (p, fy) => p.deleteInventoryRecords(null),
                provider: provider,
                financialYear: null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // SET 2: Financial Year Transaction Logs & History (5 Items)
        Row(
          children: [
            _dbActionTile(
              "Sales History",
              "Billing and itemized records",
              Icons.point_of_sale_rounded,
              Colors.blue.shade700,
              btnLabel: "EXPORT",
              headings: ["Entry No", "Date", "Time", "Patient", "Mobile", "Account", "Agent", "Product", "Packing", "Batch", "Qty", "S.Rate", "MRP", "Disc%", "Tax%", "Total", "Profit"],
              selectedFy: _salesFy,
              availableFys: availableFys,
              onFyChanged: (fy) => setState(() => _salesFy = fy),
              onTap: () => _handleSync(
                title: "Export Sales",
                action: (p, path, progress, fy) => p.exportSalesToExcel(path, onProgress: progress, financialYear: fy),
                isExport: true,
                provider: provider,
                financialYear: _salesFy,
              ),
              importTap: () => _handleSync(
                title: "Import Sales",
                action: (p, path, progress, fy) => p.importSalesFromExcel(path, onProgress: progress),
                isExport: false,
                provider: provider,
                financialYear: _salesFy,
              ),
              deleteTap: () => _handleDelete(
                title: "Sales History",
                deleteAction: (p, fy) => p.deleteSalesRecords(fy),
                provider: provider,
                financialYear: _salesFy,
              ),
            ),
            const SizedBox(width: 24),
            _dbActionTile(
              "Purchase Logs",
              "Stock acquisition history",
              Icons.local_shipping_rounded,
              Colors.indigo,
              btnLabel: "EXPORT",
              headings: ["Entry No", "Date", "Time", "Supplier", "Invoice No", "Inv Date", "Done By", "Product", "Batch", "Qty", "Packing", "P.Rate", "MRP", "Disc%", "Tax%", "Taxable Amount", "Grand Total"],
              selectedFy: _purchaseFy,
              availableFys: availableFys,
              onFyChanged: (fy) => setState(() => _purchaseFy = fy),
              onTap: () => _handleSync(
                title: "Export Purchase",
                action: (p, path, progress, fy) => p.exportPurchaseToExcel(path, onProgress: progress, financialYear: fy),
                isExport: true,
                provider: provider,
                financialYear: _purchaseFy,
              ),
              importTap: () => _handleSync(
                title: "Import Purchase",
                action: (p, path, progress, fy) => p.importPurchaseFromExcel(path, onProgress: progress),
                isExport: false,
                provider: provider,
                financialYear: _purchaseFy,
              ),
              deleteTap: () => _handleDelete(
                title: "Purchase Logs",
                deleteAction: (p, fy) => p.deletePurchaseRecords(fy),
                provider: provider,
                financialYear: _purchaseFy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _dbActionTile(
              "Sales Returns",
              "Sales return logs",
              Icons.assignment_return_rounded,
              Colors.orange.shade700,
              btnLabel: "EXPORT",
              headings: ["Entry No", "Date", "Customer", "Product", "Pack", "Total Amount", "Discount", "dis%", "gst%", "gst amt", "disc %", "Ref Invoice", "Grand Total"],
              selectedFy: _salesReturnFy,
              availableFys: availableFys,
              onFyChanged: (fy) => setState(() => _salesReturnFy = fy),
              onTap: () => _handleSync(
                title: "Export Sales Returns",
                action: (p, path, progress, fy) => p.exportSalesReturnsToExcel(path, onProgress: progress, financialYear: fy),
                isExport: true,
                provider: provider,
                financialYear: _salesReturnFy,
              ),
              importTap: () => _handleSync(
                title: "Import Sales Returns",
                action: (p, path, progress, fy) => p.importSalesReturnsFromExcel(path, onProgress: progress),
                isExport: false,
                provider: provider,
                financialYear: _salesReturnFy,
              ),
              deleteTap: () => _handleDelete(
                title: "Sales Returns",
                deleteAction: (p, fy) => p.deleteSalesReturnsRecords(fy),
                provider: provider,
                financialYear: _salesReturnFy,
              ),
            ),
            const SizedBox(width: 24),
            _dbActionTile(
              "Purchase Returns",
              "Purchase return logs",
              Icons.assignment_return_rounded,
              Colors.deepOrange.shade700,
              btnLabel: "EXPORT",
              headings: ["Entry No", "Date", "Supplier", "Product", "Pack", "Total Amount", "Discount", "Ref Purchase", "Grand Total"],
              selectedFy: _purchaseReturnFy,
              availableFys: availableFys,
              onFyChanged: (fy) => setState(() => _purchaseReturnFy = fy),
              onTap: () => _handleSync(
                title: "Export Purchase Returns",
                action: (p, path, progress, fy) => p.exportPurchaseReturnsToExcel(path, onProgress: progress, financialYear: fy),
                isExport: true,
                provider: provider,
                financialYear: _purchaseReturnFy,
              ),
              importTap: () => _handleSync(
                title: "Import Purchase Returns",
                action: (p, path, progress, fy) => p.importPurchaseReturnsFromExcel(path, onProgress: progress),
                isExport: false,
                provider: provider,
                financialYear: _purchaseReturnFy,
              ),
              deleteTap: () => _handleDelete(
                title: "Purchase Returns",
                deleteAction: (p, fy) => p.deletePurchaseReturnsRecords(fy),
                provider: provider,
                financialYear: _purchaseReturnFy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _dbActionTile(
              "Damage & Loss",
              "Inventory write-off logs",
              Icons.broken_image_rounded,
              Colors.red.shade700,
              btnLabel: "EXPORT",
              headings: ["ID", "Date", "Product", "Batch", "Quantity", "Reason", "Loss Value"],
              selectedFy: _damageFy,
              availableFys: availableFys,
              onFyChanged: (fy) => setState(() => _damageFy = fy),
              onTap: () => _handleSync(
                title: "Export Damage",
                action: (p, path, progress, fy) => p.exportDamageToExcel(path, onProgress: progress, financialYear: fy),
                isExport: true,
                provider: provider,
                financialYear: _damageFy,
              ),
              importTap: () => _handleSync(
                title: "Import Damage",
                action: (p, path, progress, fy) => p.importDamageFromExcel(path, onProgress: progress),
                isExport: false,
                provider: provider,
                financialYear: _damageFy,
              ),
              deleteTap: () => _handleDelete(
                title: "Damage & Loss",
                deleteAction: (p, fy) => p.deleteDamageRecords(fy),
                provider: provider,
                financialYear: _damageFy,
              ),
            ),
          ],
        ),
      ],
    );
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
      AppDialogs.showLoadingDialog(context, message: "Analyzing File...");
      
      final analysis = await provider.analyzeExcelForImport(filePath);
      if (!mounted) return;
      Navigator.pop(context); // Close analysis loader

      if (analysis['success'] == true) {
        bool isSales = title.toLowerCase().contains("sales");
        bool isPurchase = title.toLowerCase().contains("purchase");
        bool isReturn = title.toLowerCase().contains("return");
        bool isDamage = title.toLowerCase().contains("damage");
        bool isInventory = title.toLowerCase().contains("inventory");
        bool isProductMaster = title.toLowerCase().contains("product master") || title.toLowerCase().contains("product");
        
        dynamic result = await _showImportPreview(analysis, isSales: isSales, isPurchase: isPurchase, isReturn: isReturn, isDamage: isDamage, isInventory: isInventory, isProductMaster: isProductMaster);
        if (result == null) return;
        
        Map<String, int>? customMapping;
        if (result is Map<String, int>) {
          customMapping = result;
        }

        final selectedPath = filePath;
        provider.addSyncTask(
          title: title,
          type: 'Import',
          taskRunner: (onProgress) async {
            if (isSales) {
              return await provider.importSalesFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping, financialYear: financialYear);
            } else if (isPurchase) {
              return await provider.importPurchaseFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping, financialYear: financialYear);
            } else if (isReturn) {
              return await provider.importReturnsFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping, financialYear: financialYear);
            } else if (isDamage) {
              return await provider.importDamageFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping, financialYear: financialYear);
            } else if (isInventory) {
              return await provider.importInventoryFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping);
            } else if (isProductMaster) {
              return await provider.importProductMasterFromExcel(selectedPath, onProgress: onProgress, customMapping: customMapping);
            } else {
              return await action(provider, selectedPath, onProgress, financialYear);
            }
          },
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.blue.shade800,
              content: Text("⚡ '$title' added to Background Sync Queue! You can continue working."),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(analysis['message'] ?? "Analysis Failed")));
      }
    } else {
      final selectedPath = filePath;
      provider.addSyncTask(
        title: title,
        type: 'Export',
        taskRunner: (onProgress) async {
          final res = await action(provider, selectedPath, onProgress, financialYear);
          if (res is Map<String, dynamic>) return res;
          return {'success': true, 'message': '$title exported successfully.'};
        },
      );

      if (mounted) {
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
    required Future<Map<String, dynamic>> Function(PharmacyProvider p, String? fy) deleteAction,
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

    if (mounted) {
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

  Widget _buildBackgroundSyncMonitor(PharmacyProvider provider) {
    if (provider.syncQueue.isEmpty) return const SizedBox();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                provider.isProcessingSyncQueue ? Icons.sync : Icons.task_alt,
                color: Colors.blue.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                "Background Synchronization Queue (${provider.syncQueue.where((t) => t.status == 'In Progress' || t.status == 'Pending').length} active)",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
              ),
              const Spacer(),
              if (provider.syncQueue.any((t) => t.status == 'Completed' || t.status == 'Failed'))
                TextButton.icon(
                  onPressed: () => provider.clearCompletedSyncTasks(),
                  icon: const Icon(Icons.cleaning_services_rounded, size: 14),
                  label: const Text("Clear Finished", style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: provider.syncQueue.map((task) {
              bool isInProg = task.status == 'In Progress';
              bool isDone = task.status == 'Completed';
              bool isFailed = task.status == 'Failed';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isInProg ? Colors.blue.shade50 : isFailed ? Colors.red.shade50 : isDone ? Colors.green.shade50 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isInProg ? Colors.blue.shade300 : isFailed ? Colors.red.shade200 : isDone ? Colors.green.shade300 : Colors.grey.shade300
                  )
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isInProg)
                          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        else if (isDone)
                          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16)
                        else if (isFailed)
                          const Icon(Icons.error_rounded, color: Colors.red, size: 16)
                        else
                          const Icon(Icons.schedule_rounded, color: Colors.grey, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "${task.type.toUpperCase()}: ${task.title}",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                          ),
                        ),
                        Text(
                          isInProg ? "${(task.progress * 100).toInt()}%" : task.status,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isInProg ? Colors.blue.shade800 : isDone ? Colors.green.shade800 : isFailed ? Colors.red.shade800 : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    if (isInProg) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: task.progress, backgroundColor: Colors.blue.shade100, color: Colors.blue.shade700, minHeight: 4),
                    ],
                    if (task.resultMessage != null) ...[
                      const SizedBox(height: 4),
                      Text(task.resultMessage!, style: TextStyle(fontSize: 10, color: isFailed ? Colors.red.shade900 : Colors.black87)),
                    ]
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<dynamic> _showImportPreview(Map<String, dynamic> analysis, {bool isSales = false, bool isPurchase = false, bool isReturn = false, bool isDamage = false, bool isInventory = false, bool isProductMaster = false}) {
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
      fieldOrder = ['invoice_no', 'date', 'time', 'patient', 'mobile', 'account', 'agent', 'done_by', 'product', 'packing', 'doctor', 'batch', 'qty', 'mrp', 'total', 'disc_perc', 'disc_amt', 'gst_perc', 'gst_amt', 'profit'];
    } else if (isPurchase) {
      activeFields = purchaseFields;
      fieldOrder = ['entry_no', 'date', 'time', 'supplier', 'inv_no', 'inv_date', 'done_by', 'product', 'packing', 'batch', 'expiry', 'qty', 'f_qty', 'mrp', 'p_rate', 'total', 'disc_perc', 'disc_amt', 'gst_perc', 'gst_amt'];
    } else if (isReturn) {
      activeFields = returnFields;
      fieldOrder = ['entry_no', 'date', 'customer', 'product', 'packing', 'batch', 'qty', 'ref_invoice', 'net', 'disc_amt', 'grand_total'];
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

    String importTypeKey = isSales
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

    Map<String, int?> fieldMapping = {}; // SystemFieldKey -> ExcelColIndex

    Future<void> autoMapFields(List<String> excelHeaders) async {
      Map<String, String> savedHeaderMappings = {};
      try {
        final prefs = await SharedPreferences.getInstance();
        String? savedJson = prefs.getString("excel_import_header_mapping_$importTypeKey");
        if (savedJson != null && savedJson.isNotEmpty) {
          Map<String, dynamic> decoded = jsonDecode(savedJson);
          savedHeaderMappings = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (e) {
        debugPrint("Error loading saved header mapping: $e");
      }

      for (var fieldKey in fieldOrder) {
        int? matchedIdx;

        if (savedHeaderMappings.containsKey(fieldKey)) {
          String savedHeader = savedHeaderMappings[fieldKey]!.trim().toLowerCase();
          for (int i = 0; i < excelHeaders.length; i++) {
            if (excelHeaders[i].trim().toLowerCase() == savedHeader) {
              matchedIdx = i;
              break;
            }
          }
        }

        if (matchedIdx == null) {
          String label = activeFields[fieldKey]!.toLowerCase().trim();
          for (int i = 0; i < excelHeaders.length; i++) {
            String h = excelHeaders[i].toLowerCase().trim();
            if (h == label || h.contains(label) || label.contains(h)) {
              matchedIdx = i;
              break;
            }
          }
        }

        fieldMapping[fieldKey] = matchedIdx;
      }
    }

    Map<String, dynamic> currentAnalysis = analysis;
    bool isInitial = true;
    Set<String> errorFields = {};
    bool isMaximized = false;
    String? dialogErrorMessage;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final provider = Provider.of<PharmacyProvider>(context, listen: false);
          List<String> headers = List<String>.from(currentAnalysis['headers']);
          List<Map<String, dynamic>> fetched = List<Map<String, dynamic>>.from(currentAnalysis['fetched']);

          if (isInitial) {
            isInitial = false;
            autoMapFields(headers).then((_) {
              if (ctx.mounted) setDialogState(() {});
            });
          }

          final screenSize = MediaQuery.of(context).size;
          final dialogWidth = isMaximized ? screenSize.width * 0.99 : screenSize.width * 0.94;
          final dialogHeight = isMaximized ? screenSize.height * 0.96 : screenSize.height * 0.90;

          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.pop(ctx);
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
                      // Top Window Control Bar (Draggable + Minimize, Maximize/Resize, Close)
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
                            _windowBtn(Icons.remove, () => Navigator.pop(ctx)),
                            _windowBtn(isMaximized ? Icons.filter_none : Icons.crop_square, () {
                              setDialogState(() => isMaximized = !isMaximized);
                            }),
                            _windowBtn(Icons.close, () => Navigator.pop(ctx), isClose: true),
                          ],
                        ),
                      ),

                      // Fetch Headings Button Bar
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                FilePickerResult? result = await FilePicker.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['xlsx', 'xls', 'csv'],
                                );
                                if (result != null && result.files.single.path != null) {
                                  final newAnalysis = await provider.analyzeExcelForImport(result.files.single.path!);
                                  if (newAnalysis['success'] == true) {
                                    currentAnalysis = newAnalysis;
                                    fieldMapping.clear();
                                    headers = List<String>.from(newAnalysis['headers']);
                                    await autoMapFields(headers);
                                    if (ctx.mounted) {
                                      setDialogState(() {});
                                    }
                                  }
                                }
                              },
                              icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                              label: const Text("FETCH HEDDINGS FROM NEW EXCEL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade800, 
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Content Area
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

                      // IN-DIALOG ERROR BANNER (Always visible inside dialog, NOT obscured!)
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

                      // Pinned Footer Actions (Always visible!)
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
                              onPressed: () => Navigator.pop(ctx), 
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
                                  Map<String, String> headerMapToPersist = {};
                                  fieldMapping.forEach((fKey, idx) {
                                    if (idx != null && idx >= 0 && idx < headers.length) {
                                      headerMapToPersist[fKey] = headers[idx];
                                    }
                                  });
                                  SharedPreferences.getInstance().then((prefs) {
                                    prefs.setString("excel_import_header_mapping_$importTypeKey", jsonEncode(headerMapToPersist));
                                  });
                                } catch (e) {
                                  debugPrint("Error saving import mapping: $e");
                                }

                                Map<String, int> finalMapping = {};
                                fieldMapping.forEach((k, v) { if (v != null) finalMapping[k] = v; });
                                Navigator.pop(ctx, finalMapping.isEmpty ? true : finalMapping);
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
          headingRowHeight: 120,
          headingRowColor: WidgetStateProperty.all(Colors.blueGrey.shade50.withValues(alpha: 0.5)),
          columnSpacing: 24,
          columns: fieldOrder.map((fieldKey) {
            String label = activeFields[fieldKey]!;
            int? mappedIdx = mapping[fieldKey];
            
            // Check if this field is missing and needs red highlighting
            bool isMandatory = (isInventory || isProductMaster)
                ? (fieldKey == 'name' || fieldKey == 'product')
                : (isPurchase
                    ? ['product', 'name', 'date', 'qty', 'entry_no'].contains(fieldKey)
                    : ['product', 'name', 'date', 'qty'].contains(fieldKey));
            bool isError = errorFields.contains(fieldKey) || (isMandatory && mappedIdx == null && errorFields.isNotEmpty);
            
            return DataColumn(
              label: Container(
                width: 180,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label.toUpperCase(), 
                          style: TextStyle(
                            fontWeight: FontWeight.w900, 
                            fontSize: 11, 
                            color: isError ? Colors.red.shade800 : Colors.blueGrey, 
                            letterSpacing: 0.5
                          )
                        ),
                        if (isMandatory) const Text(" *", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: isError ? Colors.red.shade50 : Colors.white, 
                        borderRadius: BorderRadius.circular(8), 
                        border: Border.all(
                          color: isError ? Colors.red : Colors.blue.shade300, 
                          width: isError ? 2.5 : 2
                        ),
                        boxShadow: [BoxShadow(color: (isError ? Colors.red : Colors.blue).withValues(alpha: 0.08), blurRadius: 4)],
                      ),
                      child: Autocomplete<String>(
                        key: ValueKey("map_${fieldKey}_${excelHeaders.length}_${mappedIdx}_${DateTime.now().millisecondsSinceEpoch}"),
                        initialValue: TextEditingValue(text: mappedIdx != null && mappedIdx < excelHeaders.length ? excelHeaders[mappedIdx] : (isError ? "CHOOSE COLUMN" : "Skip Column")),
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          // RE-FETCH HEADERS LIVE: Always show "Skip Column" + current Excel file headers
                          final List<String> options = ["Skip Column", ...excelHeaders];
                          if (textEditingValue.text.isEmpty) return options;
                          return options.where((o) => o.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                        },
                        onSelected: (String selection) {
                          if (selection == "Skip Column") {
                            onMap(fieldKey, null);
                          } else {
                            int idx = excelHeaders.indexOf(selection);
                            onMap(fieldKey, idx);
                          }
                        },
                        fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            style: TextStyle(fontSize: 10, color: isError ? Colors.red : Colors.blue, fontWeight: FontWeight.w900),
                            decoration: InputDecoration(
                              isDense: true, 
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14), 
                              border: InputBorder.none, 
                              suffixIcon: Icon(Icons.unfold_more_rounded, size: 18, color: isError ? Colors.red : Colors.blue),
                            ),
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 8.0,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 280, // Wider for detailed headers
                                constraints: const BoxConstraints(maxHeight: 350),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      color: Colors.blueGrey.shade50,
                                      width: double.infinity,
                                      child: const Text("CHOOSE EXCEL COLUMN:", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.blueGrey)),
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
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                              color: isSkip ? Colors.red.shade50.withValues(alpha: 0.3) : null,
                                              child: Row(
                                                children: [
                                                  Icon(isSkip ? Icons.block_flipped : Icons.view_column_rounded, size: 14, color: isSkip ? Colors.red : Colors.blue),
                                                  const SizedBox(width: 12),
                                                  Expanded(child: Text(option, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSkip ? Colors.red.shade900 : Colors.black87))),
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
                String value = "-";
                if (idx != null && idx < excelHeaders.length) {
                  String excelHeader = excelHeaders[idx];
                  value = row[excelHeader]?.toString() ?? "";
                  
                  // Intelligent formatting for preview
                  if (['date', 'inv_date', 'expiry'].contains(fieldKey) && value.isNotEmpty) {
                    // 1. Handle Excel Serial Numbers
                    double? d = double.tryParse(value);
                    if (d != null && d > 1000) {
                      try {
                        DateTime dt = DateTime(1899, 12, 30).add(Duration(days: d.toInt()));
                        value = DateFormat(fieldKey == 'expiry' ? 'MM/yy' : 'dd/MM/yy').format(dt);
                      } catch (_) {}
                    } 
                    // 2. Handle ISO Strings (2027-06-30T00:00:00.000Z)
                    else if (value.contains('T') && DateTime.tryParse(value) != null) {
                      try {
                        DateTime dt = DateTime.parse(value);
                        value = DateFormat(fieldKey == 'expiry' ? 'MM/yy' : 'dd/MM/yy').format(dt);
                      } catch (_) {}
                    }
                  }
                  
                  // 3. Round GST % if within 0.1% upside or downside
                  if (['gst', 'gst_perc', 'gst_percent', 'taxper', 'tax_per', 'cgst', 'sgst'].contains(fieldKey.toLowerCase()) && value.isNotEmpty) {
                    double? d = double.tryParse(value);
                    if (d != null) {
                      double rounded = TaxCalculator.roundGstPercent(d);
                      value = rounded % 1 == 0 ? rounded.toInt().toString() : rounded.toStringAsFixed(1);
                    }
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
                      )
                    ),
                  )
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

  Widget _buildSecurityToggle({required String title, required String subtitle, required IconData icon, required bool value, required Function(bool) onChanged, bool isDisabled = false}) {
    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  Text(subtitle, style: const TextStyle(color: Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.w500)),
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

  Widget _dbActionTile(
    String title,
    String sub,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
    String btnLabel = "GENERATE",
    VoidCallback? importTap,
    String importLabel = "IMPORT",
    VoidCallback? deleteTap,
    String deleteLabel = "DELETE",
    List<String>? headings,
    String? selectedFy,
    List<String>? availableFys,
    ValueChanged<String?>? onFyChanged,
  }) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecorationOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 30),
              if (headings != null)
                IconButton(
                  onPressed: () => _showExcelHeadingsDialog(title, headings),
                  icon: Icon(Icons.info_outline_rounded, size: 20, color: Colors.grey.shade400),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                  tooltip: "View Excel Headings",
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          if (availableFys != null && onFyChanged != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Text("FY:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedFy ?? "All Years",
                        isDense: true,
                        isExpanded: true,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                        items: ["All Years", ...availableFys].map((fy) => DropdownMenuItem(value: fy, child: Text(fy))).toList(),
                        onChanged: onFyChanged,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              if (onTap != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(btnLabel, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5)),
                  ),
                ),
              if (onTap != null && importTap != null) const SizedBox(width: 6),
              if (importTap != null)
                Expanded(
                  child: ElevatedButton(
                    onPressed: importTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(importLabel, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5)),
                  ),
                ),
              if (deleteTap != null) ...[
                if (onTap != null || importTap != null) const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton(
                    onPressed: deleteTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(deleteLabel, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _performBackup(PharmacyProvider provider) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final path = await provider.performManualBackup();

      if (!mounted) return;
      Navigator.pop(context); // Close loader

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.teal),
              SizedBox(width: 8),
              Text("Backup Complete"),
            ],
          ),
          content: Text("A timestamped database backup was created successfully:\n\n$path"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      _showErrorDialog("Backup Error", e.toString());
    }
  }

  void _showRestoreHubDialog(PharmacyProvider provider) async {
    try {
      final backups = await provider.getAvailableBackups();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.history_rounded, color: Colors.deepOrange),
              SizedBox(width: 8),
              Text("Database Restore Hub"),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 350,
            child: backups.isEmpty
                ? const Center(child: Text("No backup files found. Click 'Local Backup' to create one."))
                : ListView.builder(
                    itemCount: backups.length,
                    itemBuilder: (context, idx) {
                      final b = backups[idx];
                      final File file = b['file'] as File;
                      final DateTime dt = b['date'] as DateTime;
                      final int sizeBytes = b['size'] as int;
                      final double sizeMb = sizeBytes / (1024 * 1024);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.storage_rounded, color: Colors.blue),
                          title: Text(b['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text(
                            "${DateFormat('dd/MM/yyyy hh:mm a').format(dt)} • ${sizeMb.toStringAsFixed(2)} MB",
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                            child: const Text("RESTORE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final confirm = await AppDialogs.showConfirmDialog(
                                context: ctx,
                                title: "Confirm Restore?",
                                content: "Restoring from '${b['name']}' will replace your active database. The app will reload instantly.",
                              );

                              if (confirm == true) {
                                Navigator.pop(ctx);
                                try {
                                  await provider.restoreFromBackup(file);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("Database Restored Successfully!"), backgroundColor: Colors.green),
                                    );
                                  }
                                } catch (e) {
                                  _showErrorDialog("Restore Error", e.toString());
                                }
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            ElevatedButton.icon(
              icon: const Icon(Icons.file_open_rounded, size: 16),
              label: const Text("Import .db File", style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(ctx);
                _importExternalDbBackup(provider);
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CLOSE"),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorDialog("Restore Hub Error", e.toString());
    }
  }

  void _importExternalDbBackup(PharmacyProvider provider) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final file = File(filePath);

        if (!mounted) return;
        final confirm = await AppDialogs.showConfirmDialog(
          context: context,
          title: "Confirm Database Restore?",
          content: "Restoring from '${file.path}' will replace your active database with the imported data. The app will reload instantly.",
        );

        if (confirm == true) {
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: CircularProgressIndicator()),
          );

          final success = await provider.restoreFromBackup(file);
          if (mounted && Navigator.canPop(context)) Navigator.pop(context);

          if (success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("External Database Restored Successfully!"),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      _showErrorDialog("Import Error", e.toString());
    }
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

  void _showExcelHeadingsDialog(String exportType, List<String> headings) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue, size: 28),
            const SizedBox(width: 12),
            Text("$exportType Excel Headings", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Your Excel file will have columns in this order. The system exports these names:", style: TextStyle(fontSize: 14, color: Colors.black87)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 10,
                children: headings.map((h) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Text(h, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade900)),
                )).toList(),
              ),
              const SizedBox(height: 24),
              const Text("Note: Headings are generated automatically. Use these names if importing data back.", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: headings.join("\t")));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Headings copied (Tab-separated) for Excel!"), duration: Duration(seconds: 1)));
            },
            child: const Text("COPY ALL", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ),
        ],
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
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 8,
          shadowColor: color.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
