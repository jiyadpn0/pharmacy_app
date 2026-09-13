import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../utils/theme_constants.dart';

class AccountRegistrationScreen extends StatefulWidget {
  const AccountRegistrationScreen({super.key});

  @override
  State<AccountRegistrationScreen> createState() => _AccountRegistrationScreenState();
}

class _AccountRegistrationScreenState extends State<AccountRegistrationScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  
  Account? _editingAccount;
  bool _isActive = true;
  String _searchQuery = "";
  String _selectedColor = '0xFF6366F1'; // Default Indigo

  final List<String> _attractiveColors = [
    '0xFF6366F1', '0xFF8B5CF6', '0xFFEC4899', '0xFFF97316', 
    '0xFF14B8A6', '0xFFF59E0B', '0xFF0EA5E9', '0xFF4CAF50',
    '0xFF2196F3', '0xFFEF5350', '0xFFFBC02D', '0xFF94A3B8'
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _resetForm() {
    setState(() {
      _editingAccount = null;
      _nameCtrl.clear();
      _isActive = true;
      _selectedColor = '0xFF6366F1';
    });
  }

  void _selectForEdit(Account account) {
    setState(() {
      _editingAccount = account;
      _nameCtrl.text = account.name.replaceAll(' [DELETED]', '');
      _isActive = account.isActive;
      _selectedColor = account.color;
    });
  }

  Future<void> _saveAccount() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter an Account Name!"), backgroundColor: Colors.red),
      );
      return;
    }

    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    if (_editingAccount == null) {
      final success = await provider.addAccount(name, isActive: _isActive, color: _selectedColor);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account created successfully!"), backgroundColor: Colors.green),
        );
        _resetForm();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account name already exists!"), backgroundColor: Colors.red),
        );
      }
    } else {
      final success = await provider.updateAccount(_editingAccount!.id, name, isActive: _isActive, color: _selectedColor);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account updated successfully!"), backgroundColor: Colors.green),
        );
        _resetForm();
      } else {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account name already exists!"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteAccount(Account account) async {
    if (account.name == "CASH") {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Default CASH account cannot be deleted!"), backgroundColor: Colors.red),
        );
        return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Account?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          "Are you sure you want to delete '${account.name}'?\n\nIf this account was used in previous sales, it will be marked as '${account.name} [DELETED]'.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("DELETE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final provider = Provider.of<PharmacyProvider>(context, listen: false);
      await provider.deleteAccount(account.id);
      if (mounted) {
        _resetForm();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account removed or deactivated!"), backgroundColor: Colors.orange),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PharmacyProvider>(context);
    final filteredAccounts = provider.accountMaster.where((acc) {
      if (_searchQuery.isEmpty) return true;
      return acc.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: Column(
        children: [
          // 1. TOP HEADER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6FFFA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF0D9488), size: 24),
                ),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "ACCOUNT MASTER",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E293B), letterSpacing: 0.5),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Manage Payment & Ledger Accounts",
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. TWO-PANE BODY
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT PANE: FORM ENTRY
                Container(
                  width: 350,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("ACCOUNT NAME*", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0FFFF).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFB2EBF2)),
                          ),
                          child: TextField(
                            controller: _nameCtrl,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                            decoration: const InputDecoration(
                              hintText: "e.g. Google Pay, HDFC...",
                              hintStyle: TextStyle(color: Colors.blueGrey, fontSize: 12),
                              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                  
                        const Text("ACCOUNT COLOR", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _attractiveColors.map((colorHex) {
                            bool isSelected = _selectedColor == colorHex;
                            return InkWell(
                              onTap: () => setState(() => _selectedColor = colorHex),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Color(int.parse(colorHex)),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Colors.black : Colors.transparent,
                                    width: 2,
                                  ),
                                  boxShadow: isSelected ? const [BoxShadow(color: Colors.black26, blurRadius: 4)] : null,
                                ),
                                child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                  
                        Row(
                          children: [
                            Checkbox(
                              value: _isActive,
                              activeColor: const Color(0xFF1E293B),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              onChanged: (val) => setState(() => _isActive = val ?? true),
                            ),
                            const Text("Active Status", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                          ],
                        ),
                        const SizedBox(height: 40),
                  
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _resetForm,
                                icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: Colors.blue),
                                label: const Text("NEW", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.grey.shade300),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _saveAccount,
                                icon: const Icon(Icons.save_rounded, size: 18),
                                label: const Text("SAVE", style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // RIGHT PANE: LIST TABLE
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        color: const Color(0xFF374151),
                        child: const Row(
                          children: [
                            Expanded(
                              child: Text(
                                "ACCOUNT NAME",
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              ),
                            ),
                            Text(
                              "STATUS",
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                            SizedBox(width: 80),
                          ],
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (val) => setState(() => _searchQuery = val),
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixIcon: Icon(Icons.search, size: 20, color: Colors.blueGrey),
                            hintText: "Search account...",
                            hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                            border: InputBorder.none,
                          ),
                        ),
                      ),

                      Expanded(
                        child: filteredAccounts.isEmpty
                            ? const Center(
                                child: Text("No accounts registered yet.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                              )
                            : ListView.separated(
                                itemCount: filteredAccounts.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                                itemBuilder: (context, index) {
                                  final acc = filteredAccounts[index];
                                  final isDeleted = !acc.isActive;

                                  return InkWell(
                                    onTap: () => _selectForEdit(acc),
                                    hoverColor: Colors.blue.withValues(alpha: 0.04),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: Color(int.parse(acc.color)),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              acc.name,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: isDeleted ? Colors.red.shade400 : const Color(0xFF1E293B),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            isDeleted ? "Inactive" : "Active",
                                            style: TextStyle(
                                              color: isDeleted ? Colors.red : const Color(0xFF10B981),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 24),
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 18),
                                            tooltip: "Edit",
                                            onPressed: () => _selectForEdit(acc),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                            tooltip: "Delete",
                                            onPressed: () => _deleteAccount(acc),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
