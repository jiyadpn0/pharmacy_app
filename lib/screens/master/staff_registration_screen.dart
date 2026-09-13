import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../models/erp_models.dart';
import '../../utils/theme_constants.dart';
import '../../widgets/pin_unlock_dialog.dart';

class StaffRegistrationScreen extends StatefulWidget {
  const StaffRegistrationScreen({super.key});

  @override
  State<StaffRegistrationScreen> createState() => _StaffRegistrationScreenState();
}

class _StaffRegistrationScreenState extends State<StaffRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  String _selectedRole = "Sales Agent";
  bool _isActive = true;
  Staff? _editingStaff;

  // Filter controllers for the list
  final _filterSearchCtrl = TextEditingController();
  final _filterRoleCtrl = TextEditingController();
  String _filterStatus = "ALL"; // ALL, ACTIVE, INACTIVE

  final List<String> _roleOptions = [
    "Sales Agent",
    "Billing Staff",
    "Pharmacist",
    "Manager",
    "Admin",
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _filterSearchCtrl.dispose();
    _filterRoleCtrl.dispose();
    super.dispose();
  }

  void _clear() {
    setState(() {
      _editingStaff = null;
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _codeCtrl.clear();
      _selectedRole = "Sales Agent";
      _isActive = true;
    });
  }

  void _edit(Staff s) {
    setState(() {
      _editingStaff = s;
      _nameCtrl.text = s.name;
      _phoneCtrl.text = s.phone;
      _codeCtrl.text = s.code;
      if (_roleOptions.contains(s.role)) {
        _selectedRole = s.role;
      } else if (s.role.isNotEmpty) {
        _selectedRole = s.role;
      } else {
        _selectedRole = "Sales Agent";
      }
      _isActive = s.isActive;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    if (provider.securityToggles['require_pin_edit_master'] == true) {
      bool isUnlocked = await PinUnlockDialog.show(
        context,
        provider,
        title: "Master Data Lock",
        message: "Enter Master PIN to modify staff master data.",
      );
      if (!isUnlocked) return;
    }

    final codeText = _codeCtrl.text.trim();
    final generatedCode = codeText.isNotEmpty
        ? codeText
        : "STF${(provider.staffMaster.length + 1).toString().padLeft(2, '0')}";

    final staff = Staff(
      id: _editingStaff?.id ?? "STF_${DateTime.now().millisecondsSinceEpoch}",
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      role: _selectedRole,
      code: generatedCode,
      isActive: _isActive,
    );

    if (_editingStaff == null) {
      await provider.registerStaff(staff);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Staff Registered Successfully"),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      await provider.updateStaff(staff);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Staff Details Updated Successfully"),
          backgroundColor: Colors.blue,
        ),
      );
    }

    _clear();
  }

  Future<void> _delete(Staff s) async {
    final c = AppColors.of(context);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    if (provider.securityToggles['require_pin_edit_master'] == true) {
      bool isUnlocked = await PinUnlockDialog.show(
        context,
        provider,
        title: "Master Data Lock",
        message: "Enter Master PIN to delete staff member.",
      );
      if (!isUnlocked) return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text("Delete Staff", style: TextStyle(color: c.primaryText)),
        content: Text(
          "Are you sure you want to delete staff member '${s.name}'?",
          style: TextStyle(color: c.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("CANCEL", style: TextStyle(color: c.secondaryText)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await provider.deleteStaff(s.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Staff Deleted"),
          backgroundColor: Colors.red,
        ),
      );
      if (_editingStaff?.id == s.id) {
        _clear();
      }
    }
  }

  Future<void> _toggleStatus(Staff s) async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    await provider.toggleStaffActive(s.id, !s.isActive);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "'${s.name}' is now ${!s.isActive ? 'ACTIVE' : 'INACTIVE'}",
        ),
        backgroundColor: !s.isActive ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final provider = Provider.of<PharmacyProvider>(context);
    final allStaff = provider.staffMaster;

    final totalCount = allStaff.length;
    final activeCount = allStaff.where((s) => s.isActive).length;
    final inactiveCount = totalCount - activeCount;

    // Filter staff list based on search term, role, and active status
    final filteredStaff = allStaff.where((s) {
      final query = _filterSearchCtrl.text.toLowerCase().trim();
      final matchesQuery = query.isEmpty ||
          s.name.toLowerCase().contains(query) ||
          s.code.toLowerCase().contains(query) ||
          s.phone.contains(query);

      final roleQuery = _filterRoleCtrl.text.toLowerCase().trim();
      final matchesRole = roleQuery.isEmpty || s.role.toLowerCase().contains(roleQuery);

      bool matchesStatus = true;
      if (_filterStatus == "ACTIVE") {
        matchesStatus = s.isActive;
      } else if (_filterStatus == "INACTIVE") {
        matchesStatus = !s.isActive;
      }

      return matchesQuery && matchesRole && matchesStatus;
    }).toList();

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _buildToolbar(c, totalCount, activeCount, inactiveCount),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT: Staff Registration / Edit Form
                SizedBox(
                  width: 360,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: c.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _editingStaff != null ? Icons.edit_note_rounded : Icons.person_add_alt_1_rounded,
                                  color: Colors.teal.shade400,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _editingStaff != null ? "EDIT STAFF MEMBER" : "REGISTER NEW STAFF",
                                  style: TextStyle(
                                    color: c.primaryText,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),

                            // Staff Code
                            Text("Staff Code / ID", style: TextStyle(color: c.secondaryText, fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            TextFormField(
                              controller: _codeCtrl,
                              style: TextStyle(color: c.primaryText, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: "Auto-generated (e.g. STF01)",
                                hintStyle: TextStyle(color: c.secondaryText.withValues(alpha: 0.5), fontSize: 12),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                filled: true,
                                fillColor: c.inputBg,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Full Name
                            Text("Full Name *", style: TextStyle(color: c.secondaryText, fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            TextFormField(
                              controller: _nameCtrl,
                              style: TextStyle(color: c.primaryText, fontSize: 13),
                              validator: (val) => (val == null || val.trim().isEmpty) ? "Enter staff name" : null,
                              decoration: InputDecoration(
                                hintText: "e.g. Rahul Sharma",
                                hintStyle: TextStyle(color: c.secondaryText.withValues(alpha: 0.5), fontSize: 12),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                filled: true,
                                fillColor: c.inputBg,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Mobile / Phone
                            Text("Mobile / Phone", style: TextStyle(color: c.secondaryText, fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              style: TextStyle(color: c.primaryText, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: "10-digit mobile number",
                                hintStyle: TextStyle(color: c.secondaryText.withValues(alpha: 0.5), fontSize: 12),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                filled: true,
                                fillColor: c.inputBg,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Role / Designation
                            Text("Role / Designation", style: TextStyle(color: c.secondaryText, fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              value: _roleOptions.contains(_selectedRole) ? _selectedRole : _roleOptions.first,
                              dropdownColor: c.surface,
                              style: TextStyle(color: c.primaryText, fontSize: 13),
                              decoration: InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                filled: true,
                                fillColor: c.inputBg,
                              ),
                              items: _roleOptions.map((role) {
                                return DropdownMenuItem<String>(
                                  value: role,
                                  child: Text(role),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedRole = val);
                              },
                            ),
                            const SizedBox(height: 16),

                            // Is Active Toggle
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: _isActive ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isActive ? Colors.green.shade400 : Colors.orange.shade400,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _isActive ? Icons.check_circle_rounded : Icons.pause_circle_filled_rounded,
                                        color: _isActive ? Colors.green : Colors.orange,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isActive ? "Status: ACTIVE" : "Status: INACTIVE",
                                        style: TextStyle(
                                          color: _isActive ? Colors.green.shade700 : Colors.orange.shade700,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Switch(
                                    value: _isActive,
                                    activeColor: Colors.green,
                                    onChanged: (val) => setState(() => _isActive = val),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Form Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _save,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _editingStaff != null ? Colors.blue.shade700 : Colors.teal.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: Icon(_editingStaff != null ? Icons.save_rounded : Icons.add_rounded, size: 18),
                                    label: Text(
                                      _editingStaff != null ? "UPDATE" : "SAVE STAFF",
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: _clear,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    side: BorderSide(color: c.border),
                                  ),
                                  child: Text("CLEAR", style: TextStyle(color: c.secondaryText, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                VerticalDivider(width: 1, color: c.border),

                // RIGHT: Staff Master List / Table
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        // Search & Filter Row
                        _buildFilterHeader(c),
                        const SizedBox(height: 12),

                        // Table Grid Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(width: 80, child: Text("CODE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(flex: 3, child: Text("STAFF NAME", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(flex: 2, child: Text("ROLE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(flex: 2, child: Text("PHONE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                              SizedBox(width: 100, child: Text("STATUS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                              SizedBox(width: 130, child: Text("ACTIONS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                            ],
                          ),
                        ),

                        // Table Grid Content
                        Expanded(
                          child: filteredStaff.isEmpty
                              ? Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: c.cardBg,
                                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                                    border: Border.all(color: c.border),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.badge_outlined, size: 48, color: c.secondaryText.withValues(alpha: 0.4)),
                                      const SizedBox(height: 12),
                                      Text("No staff members found matching criteria", style: TextStyle(color: c.secondaryText, fontSize: 14)),
                                    ],
                                  ),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: c.cardBg,
                                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                                    border: Border.all(color: c.border),
                                  ),
                                  child: ListView.separated(
                                    itemCount: filteredStaff.length,
                                    separatorBuilder: (_, __) => Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
                                    itemBuilder: (context, index) {
                                      final staff = filteredStaff[index];
                                      final isEditing = _editingStaff?.id == staff.id;

                                      return Container(
                                        color: isEditing
                                            ? Colors.teal.withValues(alpha: 0.1)
                                            : (index % 2 == 0 ? c.surface : c.cardBg),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        child: Row(
                                          children: [
                                            // CODE
                                            SizedBox(
                                              width: 80,
                                              child: Text(
                                                staff.code.isNotEmpty ? staff.code : "STF",
                                                style: TextStyle(
                                                  color: c.primaryText,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),

                                            // NAME
                                            Expanded(
                                              flex: 3,
                                              child: Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 12,
                                                    backgroundColor: _getRoleColor(staff.role).withValues(alpha: 0.2),
                                                    child: Text(
                                                      staff.name.isNotEmpty ? staff.name[0].toUpperCase() : "S",
                                                      style: TextStyle(
                                                        color: _getRoleColor(staff.role),
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      staff.name,
                                                      style: TextStyle(
                                                        color: c.primaryText,
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 13,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // ROLE
                                            Expanded(
                                              flex: 2,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: _getRoleColor(staff.role).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: _getRoleColor(staff.role).withValues(alpha: 0.4)),
                                                ),
                                                child: Text(
                                                  staff.role,
                                                  style: TextStyle(
                                                    color: _getRoleColor(staff.role),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),

                                            // PHONE
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                staff.phone.isNotEmpty ? staff.phone : "-",
                                                style: TextStyle(color: c.secondaryText, fontSize: 12),
                                              ),
                                            ),

                                            // STATUS BADGE
                                            SizedBox(
                                              width: 100,
                                              child: InkWell(
                                                onTap: () => _toggleStatus(staff),
                                                borderRadius: BorderRadius.circular(12),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: staff.isActive
                                                        ? Colors.green.withValues(alpha: 0.15)
                                                        : Colors.grey.withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: staff.isActive ? Colors.green.shade400 : Colors.grey.shade500,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        width: 6,
                                                        height: 6,
                                                        decoration: BoxDecoration(
                                                          shape: BoxShape.circle,
                                                          color: staff.isActive ? Colors.green : Colors.grey,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        staff.isActive ? "ACTIVE" : "INACTIVE",
                                                        style: TextStyle(
                                                          color: staff.isActive ? Colors.green.shade700 : Colors.grey.shade600,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // ACTIONS
                                            SizedBox(
                                              width: 130,
                                              child: Row(
                                                children: [
                                                  Tooltip(
                                                    message: staff.isActive ? "Set Inactive" : "Set Active",
                                                    child: Switch(
                                                      value: staff.isActive,
                                                      activeColor: Colors.green,
                                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      onChanged: (_) => _toggleStatus(staff),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blue),
                                                    onPressed: () => _edit(staff),
                                                    tooltip: "Edit Staff",
                                                    constraints: const BoxConstraints(maxHeight: 32, maxWidth: 32),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                                    onPressed: () => _delete(staff),
                                                    tooltip: "Delete Staff",
                                                    constraints: const BoxConstraints(maxHeight: 32, maxWidth: 32),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(AppThemeColors c, int total, int active, int inactive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.badge_rounded, color: Colors.teal.shade400, size: 22),
          const SizedBox(width: 10),
          Text(
            "STAFF MANAGEMENT",
            style: TextStyle(
              color: c.primaryText,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 20),

          // Counters
          _buildCountChip("TOTAL: $total", Colors.blue, c),
          const SizedBox(width: 8),
          _buildCountChip("ACTIVE: $active", Colors.green, c),
          const SizedBox(width: 8),
          _buildCountChip("INACTIVE: $inactive", Colors.orange, c),

          const Spacer(),

          ElevatedButton.icon(
            onPressed: _clear,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: const Icon(Icons.person_add_rounded, size: 16),
            label: const Text("NEW STAFF", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCountChip(String label, Color color, AppThemeColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildFilterHeader(AppThemeColors c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          // Search Name / Code / Phone
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _filterSearchCtrl,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: c.primaryText, fontSize: 12),
                decoration: InputDecoration(
                  hintText: "Search by Name, Code or Phone...",
                  hintStyle: TextStyle(color: c.secondaryText, fontSize: 12),
                  prefixIcon: Icon(Icons.search_rounded, size: 16, color: c.secondaryText),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  filled: true,
                  fillColor: c.inputBg,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Role Filter
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _filterRoleCtrl,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: c.primaryText, fontSize: 12),
                decoration: InputDecoration(
                  hintText: "Filter by Role...",
                  hintStyle: TextStyle(color: c.secondaryText, fontSize: 12),
                  prefixIcon: Icon(Icons.work_outline_rounded, size: 16, color: c.secondaryText),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  filled: true,
                  fillColor: c.inputBg,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Status Filter Dropdown
          SizedBox(
            height: 34,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: c.inputBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filterStatus,
                  dropdownColor: c.surface,
                  style: TextStyle(color: c.primaryText, fontSize: 12, fontWeight: FontWeight.bold),
                  items: const [
                    DropdownMenuItem(value: "ALL", child: Text("Status: ALL")),
                    DropdownMenuItem(value: "ACTIVE", child: Text("Status: ACTIVE")),
                    DropdownMenuItem(value: "INACTIVE", child: Text("Status: INACTIVE")),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _filterStatus = val);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case "admin": return Colors.indigo;
      case "manager": return Colors.purple;
      case "pharmacist": return Colors.teal;
      case "billing staff": return Colors.blue;
      case "sales agent": return Colors.orange;
      default: return Colors.blueGrey;
    }
  }
}
