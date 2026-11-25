import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';
import '../database/db_helper.dart';

/// Interactive First-Run / Pharmacy Setup Wizard
/// Guides the user through basic store profile, default accounting, and starter data seeding
class FirstRunWizardDialog extends StatefulWidget {
  final VoidCallback? onCompleted;

  const FirstRunWizardDialog({super.key, this.onCompleted});

  static Future<bool> checkAndShow(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isSetupDone = prefs.getBool('first_run_setup_v1_completed') ?? false;
      if (!isSetupDone && context.mounted) {
        final result = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const FirstRunWizardDialog(),
        );
        return result ?? false;
      }
    } catch (_) {}
    return false;
  }

  @override
  State<FirstRunWizardDialog> createState() => _FirstRunWizardDialogState();
}

class _FirstRunWizardDialogState extends State<FirstRunWizardDialog> {
  int _currentStep = 0;
  bool _isSaving = false;

  // Step 1: Store Profile
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _dlCtrl = TextEditingController();
  final _gstCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController(text: "Professional Pharmacy Care");

  // Step 2: System & Invoicing Preferences
  String _invoicePrefix = "INV-";
  String _terminalId = "POS-01";
  String _printerMode = "thermal80"; // thermal80, a4, a5
  bool _seedStarterCategories = true;
  bool _seedStarterRacks = true;
  bool _seedStarterAccounts = true;

  @override
  void initState() {
    super.initState();
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    final cp = pharma.companyProfile;
    _nameCtrl.text = cp.name.isNotEmpty && !cp.name.contains("SAHAKAR") ? cp.name : "";
    _addressCtrl.text = cp.address.isNotEmpty && !cp.address.contains("KALPETTA") ? cp.address : "";
    _phoneCtrl.text = cp.phone.isNotEmpty && !cp.phone.contains("0000000000") ? cp.phone : "";
    _emailCtrl.text = cp.email.isNotEmpty && !cp.email.contains("sahakar") ? cp.email : "";
    _dlCtrl.text = cp.dlNumber.isNotEmpty && !cp.dlNumber.contains("123/2024") ? cp.dlNumber : "";
    _gstCtrl.text = cp.gstIn.isNotEmpty && !cp.gstIn.contains("32AAAAA0000A1Z5") ? cp.gstIn : "";
    if (cp.tagline.isNotEmpty) {
      _taglineCtrl.text = cp.tagline;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _dlCtrl.dispose();
    _gstCtrl.dispose();
    _taglineCtrl.dispose();
    super.dispose();
  }

  Future<void> _completeSetup() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final pharma = Provider.of<PharmacyProvider>(context, listen: false);
      final app = Provider.of<AppProvider>(context, listen: false);
      final db = await DbHelper.instance.database;
      final prefs = await SharedPreferences.getInstance();

      // 1. Save Company Profile
      final newProfile = CompanyProfile(
        name: _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : "My Pharmacy",
        address: _addressCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        dlNumber: _dlCtrl.text.trim(),
        gstIn: _gstCtrl.text.trim().toUpperCase(),
        tagline: _taglineCtrl.text.trim(),
      );
      await pharma.saveCompanyProfile(newProfile);

      // 2. Save Preferences
      await prefs.setString('invoice_series_prefix', _invoicePrefix.trim());
      await prefs.setString('terminal_id', _terminalId.trim());
      await prefs.setString('preferred_printer_type', _printerMode);
      await prefs.setBool('first_run_setup_v1_completed', true);

      // 3. Seed Starter Data
      if (_seedStarterCategories) {
        final categories = [
          {'id': 'CAT_TAB', 'name': 'Tablets & Capsules'},
          {'id': 'CAT_SYR', 'name': 'Syrups & Suspensions'},
          {'id': 'CAT_INJ', 'name': 'Injections'},
          {'id': 'CAT_OINT', 'name': 'Ointments & Creams'},
          {'id': 'CAT_DROP', 'name': 'Eye & Ear Drops'},
          {'id': 'CAT_SURG', 'name': 'Surgical & Bandages'},
          {'id': 'CAT_GEN', 'name': 'General & OTC'},
        ];
        for (var c in categories) {
          await db.insert('categories', {
            'id': c['id'],
            'name': c['name'],
            'is_active': 1,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }

      if (_seedStarterRacks) {
        final racks = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'Counter Shelf', 'Fridge / Cold Chain'];
        for (var r in racks) {
          await db.insert('racks', {
            'id': 'RACK_${r.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toUpperCase()}',
            'name': r,
            'is_active': 1,
            'status_date': DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }

      if (_seedStarterAccounts) {
        final accounts = [
          {'id': 'ACC_CASH', 'name': 'CASH', 'color': '0xFF4CAF50'},
          {'id': 'ACC_UPI', 'name': 'UPI / QR', 'color': '0xFF2196F3'},
          {'id': 'ACC_CARD', 'name': 'CARD / POS', 'color': '0xFF9C27B0'},
          {'id': 'ACC_CREDIT', 'name': 'CREDIT / UDHAR', 'color': '0xFFFF9800'},
        ];
        for (var a in accounts) {
          await db.insert('accounts', {
            'id': a['id'],
            'name': a['name'],
            'type': 'Payment',
            'balance': 0.0,
            'is_active': 1,
            'color': a['color'],
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }

      await pharma.loadFromDatabase();

      if (mounted) {
        Navigator.of(context).pop(true);
        widget.onCompleted?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Pharmacy Setup Completed Successfully! Welcome to Pharma Pro ERP."),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 4),
          ),
        );

        // Open Opening Stock Entry automatically so user can enter initial shop inventory
        app.openOpeningStock();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving setup: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 720,
        height: 580,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF334155), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.rocket_launch_rounded, color: Color(0xFF3B82F6), size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Welcome to Pharma Pro ERP",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        "Complete initial setup to make the system ready for live counter billing",
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                // Step Indicator Pills
                Row(
                  children: [
                    _buildStepDot(0, "Store"),
                    const SizedBox(width: 6),
                    _buildStepDot(1, "Billing"),
                    const SizedBox(width: 6),
                    _buildStepDot(2, "Finish"),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Color(0xFF334155), height: 1),
            const SizedBox(height: 16),

            // Content Area
            Expanded(
              child: _isSaving
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF3B82F6)),
                          SizedBox(height: 16),
                          Text("Initializing Pharmacy Database & Preferences...", style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    )
                  : IndexedStack(
                      index: _currentStep,
                      children: [
                        _buildStep1StoreDetails(),
                        _buildStep2SystemPrefs(),
                        _buildStep3Ready(),
                      ],
                    ),
            ),

            const SizedBox(height: 16),
            const Divider(color: Color(0xFF334155), height: 1),
            const SizedBox(height: 16),

            // Bottom Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentStep > 0 && !_isSaving)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _currentStep--),
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text("Back"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Color(0xFF475569)),
                    ),
                  )
                else
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text("Skip for now", style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                  ),
                ElevatedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () {
                          if (_currentStep == 0) {
                            if (_nameCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Please enter your Pharmacy Name"), backgroundColor: Colors.orange),
                              );
                              return;
                            }
                            setState(() => _currentStep = 1);
                          } else if (_currentStep == 1) {
                            setState(() => _currentStep = 2);
                          } else {
                            _completeSetup();
                          }
                        },
                  icon: Icon(
                    _currentStep == 2 ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                    size: 16,
                  ),
                  label: Text(
                    _currentStep == 2 ? "Complete Setup & Open Inventory" : "Continue",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _currentStep == 2 ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepDot(int step, String title) {
    final bool isActive = _currentStep == step;
    final bool isPassed = _currentStep > step;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF3B82F6)
            : isPassed
                ? const Color(0xFF10B981).withValues(alpha: 0.2)
                : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? const Color(0xFF60A5FA)
              : isPassed
                  ? const Color(0xFF10B981)
                  : const Color(0xFF334155),
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: isActive || isPassed ? Colors.white : const Color(0xFF64748B),
          fontSize: 11,
          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildStep1StoreDetails() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "STEP 1: Pharmacy Profile & Drug License",
            style: TextStyle(color: Color(0xFF93C5FD), fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildField("Pharmacy / Medical Store Name *", _nameCtrl, hint: "e.g., City Medicos & Surgicals"),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildField("Drug License No (DL 20B/21B)", _dlCtrl, hint: "e.g., DL/KL/WYD/12345")),
              const SizedBox(width: 12),
              Expanded(child: _buildField("GSTIN Number", _gstCtrl, hint: "e.g., 32AAAAA0000A1Z5")),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildField("Contact Phone Number", _phoneCtrl, hint: "e.g., +91 9876543210")),
              const SizedBox(width: 12),
              Expanded(child: _buildField("Store Email Address", _emailCtrl, hint: "e.g., contact@citymedicos.com")),
            ],
          ),
          const SizedBox(height: 10),
          _buildField("Shop Address", _addressCtrl, hint: "Shop No. 4, Ground Floor, Main Road, City", maxLines: 2),
          const SizedBox(height: 10),
          _buildField("Invoice Tagline / Subtitle", _taglineCtrl, hint: "e.g., 24x7 Chemist & Druggist, Free Home Delivery"),
        ],
      ),
    );
  }

  Widget _buildStep2SystemPrefs() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "STEP 2: Billing & Starter Masters",
            style: TextStyle(color: Color(0xFF93C5FD), fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Sales Invoice Prefix", style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 4),
                    TextFormField(
                      initialValue: _invoicePrefix,
                      onChanged: (val) => _invoicePrefix = val,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _inputDecoration("e.g. INV- or BILL-"),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Terminal / Counter ID", style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 4),
                    TextFormField(
                      initialValue: _terminalId,
                      onChanged: (val) => _terminalId = val,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _inputDecoration("POS-01"),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text("Default Receipt Printer", style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildPrinterChoice("thermal80", "3-inch Thermal (80mm)", Icons.receipt_long_rounded),
              const SizedBox(width: 10),
              _buildPrinterChoice("a4", "A4 Laser / Desktop", Icons.description_rounded),
              const SizedBox(width: 10),
              _buildPrinterChoice("a5", "A5 Half-Page", Icons.article_rounded),
            ],
          ),
          const SizedBox(height: 18),
          const Text("Pre-populate Standard Pharmacy Masters:", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildCheckbox("Seed standard drug categories (Tablets, Syrups, Injections, Ointments)", _seedStarterCategories, (v) => setState(() => _seedStarterCategories = v ?? true)),
          _buildCheckbox("Seed standard pharmacy shelf racks (A1, A2, B1, Cold Chain)", _seedStarterRacks, (v) => setState(() => _seedStarterRacks = v ?? true)),
          _buildCheckbox("Seed standard payment accounts (Cash, UPI/QR, Card, Credit/Udhar)", _seedStarterAccounts, (v) => setState(() => _seedStarterAccounts = v ?? true)),
        ],
      ),
    );
  }

  Widget _buildStep3Ready() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 48),
        ),
        const SizedBox(height: 18),
        const Text(
          "Your Pharmacy is Ready!",
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            "Store profile, categories, shelf racks, and accounting channels will be created for '${_nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : "My Pharmacy"}'.\n\nNext, the system will open the Opening Stock Entry screen where you can add or import your current shop stock.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {String hint = "", int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  Widget _buildPrinterChoice(String value, String label, IconData icon) {
    final bool isSelected = _printerMode == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _printerMode = value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3B82F6).withValues(alpha: 0.2) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF334155),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? const Color(0xFF60A5FA) : const Color(0xFF94A3B8), size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF3B82F6),
              side: const BorderSide(color: Color(0xFF64748B)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12)),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
      filled: true,
      fillColor: const Color(0xFF1E293B),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
    );
  }
}
