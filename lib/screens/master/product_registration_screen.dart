import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../providers/app_provider.dart';
import '../../widgets/pin_unlock_dialog.dart';
import '../../utils/theme_constants.dart';

class ProductRegistrationScreen extends StatefulWidget {
  final String? initialName;
  final bool isCompact;
  const ProductRegistrationScreen({super.key, this.initialName, this.isCompact = false});

  @override
  State<ProductRegistrationScreen> createState() => _ProductRegistrationScreenState();
}

class _ProductRegistrationScreenState extends State<ProductRegistrationScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _hsnCtrl = TextEditingController();
  final TextEditingController _reorderCtrl = TextEditingController();
  final TextEditingController _maxCtrl = TextEditingController();
  final TextEditingController _packingCtrl = TextEditingController();
  final TextEditingController _leadTimeCtrl = TextEditingController(text: "2");
  final TextEditingController _discCtrl = TextEditingController();
  final TextEditingController _barcodeCtrl = TextEditingController();
  final TextEditingController _aliasCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _genericCtrl = TextEditingController();

  // FOCUS NODES
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _hsnFocus = FocusNode();
  final FocusNode _aliasFocus = FocusNode();
  final FocusNode _rackFocus = FocusNode();
  final FocusNode _patentFocus = FocusNode();
  final FocusNode _reorderFocus = FocusNode();
  final FocusNode _maxFocus = FocusNode();
  final FocusNode _categoryFocus = FocusNode();
  final FocusNode _genericFocus = FocusNode();
  final FocusNode _packingFocus = FocusNode();
  final FocusNode _leadTimeFocus = FocusNode();
  final FocusNode _scheduleFocus = FocusNode();
  final FocusNode _discFocus = FocusNode();
  final FocusNode _barcodeFocus = FocusNode();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _gstFocus = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();

  int _highlightedSearchIndex = 0;

  String _selectedCategory = "Branded";
  String _selectedRack = "A1";
  String _selectedPatent = "Select Patent";
  String _selectedGeneric = "Select Generic";
  String _selectedSchedule = "Select";
  String _selectedGst = "12";
  String _selectedWholesale = "Select Wholesale";

  bool _isControlled = false;
  bool _isBanned = false;
  bool _isNrx = false;
  bool _isActive = true;
  bool _isDiscLocked = false;

  Product? _editingProduct;

  String _generatedId = "";

  @override
  void initState() {
    super.initState();
    _generatedId = _generate10DigitId();
    if (widget.initialName != null) {
      _nameCtrl.text = widget.initialName!;
    }
    _setupFocusListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialName != null && widget.initialName!.isNotEmpty) {
        _hsnFocus.requestFocus();
      } else {
        _nameFocus.requestFocus();
      }
    });
  }

  String _generate10DigitId() {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    return provider.generateUniqueId();
  }

  void _setupFocusListeners() {
    final Map<FocusNode, TextEditingController> focusMap = {
      _nameFocus: _nameCtrl,
      _hsnFocus: _hsnCtrl,
      _reorderFocus: _reorderCtrl,
      _maxFocus: _maxCtrl,
      _packingFocus: _packingCtrl,
      _discFocus: _discCtrl,
      _barcodeFocus: _barcodeCtrl,
      _searchFocus: _searchCtrl,
      _genericFocus: _genericCtrl,
    };

    focusMap.forEach((node, ctrl) {
      node.addListener(() {
        if (node.hasFocus) {
          Future.microtask(() {
            if (ctrl.text.isNotEmpty) {
              ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
            }
          });
        }
      });
    });
  }

  @override
  void dispose() {
    for (var ctrl in [_nameCtrl, _hsnCtrl, _reorderCtrl, _maxCtrl, _packingCtrl, _discCtrl, _barcodeCtrl, _searchCtrl, _genericCtrl]) {
      ctrl.dispose();
    }
    for (var f in [_nameFocus, _hsnFocus, _rackFocus, _patentFocus, _reorderFocus, _maxFocus, _categoryFocus, _genericFocus, _packingFocus, _scheduleFocus, _discFocus, _barcodeFocus, _searchFocus, _gstFocus, _keyboardFocusNode]) {
      f.dispose();
    }
    super.dispose();
  }

  List<String> _getPatentOptions(PharmacyProvider provider) {
    final Set<String> set = {"Select Patent"};
    for (var m in provider.manufacturers) {
      if (m.trim().isNotEmpty) set.add(m.trim());
    }
    for (var p in provider.productMaster) {
      if (p.patent.trim().isNotEmpty) set.add(p.patent.trim());
      if (p.manufacturer.trim().isNotEmpty) set.add(p.manufacturer.trim());
    }
    for (var p in provider.products) {
      if (p.patent.trim().isNotEmpty) set.add(p.patent.trim());
      if (p.manufacturer.trim().isNotEmpty) set.add(p.manufacturer.trim());
    }
    if (_selectedPatent.isNotEmpty && _selectedPatent != "Select Patent") {
      set.add(_selectedPatent.trim());
    }
    final list = set.toList();
    list.remove("Select Patent");
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ["Select Patent", ...list];
  }

  List<String> _getCategoryOptions(PharmacyProvider provider) {
    final Set<String> set = {"Branded", "Generic", "Branded Generic", "General"};
    for (var c in provider.categories) {
      if (c.trim().isNotEmpty) set.add(c.trim());
    }
    for (var p in provider.productMaster) {
      if (p.category.trim().isNotEmpty) set.add(p.category.trim());
    }
    for (var p in provider.products) {
      if (p.category.trim().isNotEmpty) set.add(p.category.trim());
    }
    if (_selectedCategory.isNotEmpty) {
      set.add(_selectedCategory.trim());
    }
    final list = set.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<String> _getGenericOptions(PharmacyProvider provider) {
    final Set<String> set = {"Select Generic"};
    for (var g in provider.generics) {
      if (g.trim().isNotEmpty) set.add(g.trim());
    }
    for (var p in provider.productMaster) {
      if (p.genericName.trim().isNotEmpty) set.add(p.genericName.trim());
    }
    for (var p in provider.products) {
      if (p.genericName.trim().isNotEmpty) set.add(p.genericName.trim());
    }
    if (_selectedGeneric.isNotEmpty && _selectedGeneric != "Select Generic") {
      set.add(_selectedGeneric.trim());
    }
    final list = set.toList();
    list.remove("Select Generic");
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ["Select Generic", ...list];
  }

  void _selectProduct(Product p) {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    provider.trackProductModified(p);
    setState(() {
      _highlightedSearchIndex = 0;
      _editingProduct = p;
      _nameCtrl.text = p.name;
      _hsnCtrl.text = p.hsnCode;
      _barcodeCtrl.text = p.batch;
      _aliasCtrl.text = p.alias;
      _selectedRack = p.rack.isNotEmpty ? p.rack : "A1";
      _selectedCategory = p.category.isNotEmpty ? p.category : "Branded";
      _selectedPatent = p.patent.isNotEmpty ? p.patent : (p.manufacturer.isNotEmpty ? p.manufacturer : "Select Patent");
      _selectedGeneric = p.genericName.isEmpty ? "Select Generic" : p.genericName;
      _genericCtrl.text = p.genericName;
      _selectedSchedule = p.schedule.isEmpty ? "Select" : p.schedule;
      _selectedWholesale = p.preferredWholesale.isEmpty ? "Select Wholesale" : p.preferredWholesale;
      _reorderCtrl.text = p.reorderLevel.toString();
      _maxCtrl.text = p.maxLevel.toString();
      _leadTimeCtrl.text = p.leadTime.toString();

      double gst = p.gstPercent;
      if ([0.0, 5.0, 12.0, 18.0].contains(gst)) {
        _selectedGst = gst.toInt().toString();
      } else {
        _selectedGst = "12";
      }

      _packingCtrl.text = p.packSize.toString();
      _discCtrl.text = p.sDiscPercent.toStringAsFixed(1);
      _isControlled = p.isControlled;
      _isBanned = p.isBanned;
      _isNrx = p.isNrx;
      _isActive = p.isActive;
      _isDiscLocked = p.isDiscLocked;
    });
    _nameFocus.requestFocus();
  }

  void _save() async {
    final enteredName = _nameCtrl.text.trim();
    if (enteredName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name is required")));
      _nameFocus.requestFocus();
      return;
    }

    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    if (provider.securityToggles['require_pin_edit_master'] == true) {
      bool isUnlocked = await PinUnlockDialog.show(
          context,
          provider,
          title: "Master Data Lock",
          message: "Enter Master PIN to modify product master data."
      );
      if (!isUnlocked) return;
    }

    final enteredNameLower = enteredName.toLowerCase();
    bool isDuplicate = false;
    String existingId = "";

    if (_editingProduct == null) {
      for (var p in provider.productMaster) {
        if (p.name.trim().toLowerCase() == enteredNameLower) {
          isDuplicate = true;
          existingId = p.id;
          break;
        }
      }
      if (!isDuplicate) {
        for (var p in provider.products) {
          if (p.name.trim().toLowerCase() == enteredNameLower) {
            isDuplicate = true;
            existingId = p.id;
            break;
          }
        }
      }
    } else {
      for (var p in provider.productMaster) {
        if (p.id != _editingProduct!.id && p.name.trim().toLowerCase() == enteredNameLower) {
          isDuplicate = true;
          existingId = p.id;
          break;
        }
      }
      if (!isDuplicate) {
        for (var p in provider.products) {
          if (p.id != _editingProduct!.id && p.name.trim().toLowerCase() == enteredNameLower) {
            isDuplicate = true;
            existingId = p.id;
            break;
          }
        }
      }
    }

    if (isDuplicate) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Text(
                "DUPLICATE ENTRY WARNING",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "You are making a duplicate entry!",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "A medicine with the name '$enteredName' already exists in Product Master${existingId.isNotEmpty ? ' (ID: $existingId)' : ''}.",
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              const Text(
                "This entry will NOT be saved to prevent duplicate records.",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return; // STOP EXECUTION - DON'T SAVE
    }

    final patentVal = _selectedPatent == "Select Patent" ? "" : _selectedPatent;
    final String gText = _genericCtrl.text.trim();
    final String genericVal = (gText.isNotEmpty && gText != "Select Generic")
        ? gText
        : (_selectedGeneric == "Select Generic" ? "" : _selectedGeneric);
    final scheduleVal = _selectedSchedule == "Select" ? "" : _selectedSchedule;
    final wholesaleVal = _selectedWholesale == "Select Wholesale" ? "" : _selectedWholesale;

    final p = Product(
      id: _editingProduct?.id ?? _generatedId,
      name: enteredName,
      hsnCode: _hsnCtrl.text.trim(),
      batch: _barcodeCtrl.text.trim(),
      rack: _selectedRack,
      category: _selectedCategory,
      patent: patentVal,
      manufacturer: patentVal,
      genericName: genericVal,
      packSize: int.tryParse(_packingCtrl.text) ?? 1,
      schedule: scheduleVal,
      gstPercent: double.tryParse(_selectedGst) ?? 12.0,
      sDiscPercent: double.tryParse(_discCtrl.text) ?? 0.0,
      reorderLevel: int.tryParse(_reorderCtrl.text) ?? 0,
      maxLevel: int.tryParse(_maxCtrl.text) ?? 0,
      isControlled: _isControlled,
      isBanned: _isBanned,
      isNrx: _isNrx,
      isActive: _isActive,
      isDiscLocked: _isDiscLocked,
      preferredWholesale: wholesaleVal,
      leadTime: int.tryParse(_leadTimeCtrl.text) ?? 2,
      alias: _aliasCtrl.text.trim(),
    );

    if (_editingProduct != null) {
      provider.updateProduct(p);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.blue, content: Text("Product Updated!")));
    } else {
      provider.addProduct(p);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("Product Registered!")));
    }
    provider.trackProductModified(p);

    if (widget.initialName != null) {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      if (appProvider.openTabs.any((t) => t.title == "PRODUCT REGISTRATION")) {
        appProvider.closeTab(appProvider.activeTabIndex);
        return;
      }
      final localNav = Navigator.of(context, rootNavigator: false);
      if (localNav.canPop()) {
        localNav.pop(p);
        return;
      }
    }

    _clear();
    _nameFocus.requestFocus();
  }

  void _clear() {
    setState(() {
      _editingProduct = null;
      _generatedId = _generate10DigitId();
      _nameCtrl.clear(); _hsnCtrl.clear(); _barcodeCtrl.clear(); _aliasCtrl.clear();
      _genericCtrl.clear();
      _packingCtrl.clear(); _reorderCtrl.clear(); _maxCtrl.clear();
      _discCtrl.clear(); _leadTimeCtrl.text = "2";
      _selectedCategory = "Branded"; _selectedRack = "A1";
      _selectedPatent = "Select Patent"; _selectedGeneric = "Select Generic";
      _selectedSchedule = "Select"; _selectedGst = "12";
      _selectedWholesale = "Select Wholesale";
      _isControlled = false; _isBanned = false; _isNrx = false; _isActive = true;
      _isDiscLocked = false;
    });
  }

  void _handleGlobalKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.f6) {
        _save();
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        _clear();
        _nameFocus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final provider = Provider.of<PharmacyProvider>(context);
    bool compact = widget.isCompact || widget.initialName != null;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      onKeyEvent: _handleGlobalKey,
      child: Scaffold(
        backgroundColor: c.background,
        body: Column(
          children: [
            _buildToolbar(provider, isCompact: compact),
            Expanded(
              child: compact
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 580),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeaderSectionSimple(),
                              const SizedBox(height: 16),
                              _buildSimpleGrid(provider),
                              const Divider(height: 32),
                              _buildStatusToggles(),
                              const SizedBox(height: 12),
                              const Text("F6: Save • ESC: Clear • TAB: Navigate",
                                  style: TextStyle(color: Colors.grey, fontSize: 10, fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        // FORM PANEL (Left Side - 45%)
                        Expanded(
                          flex: 5,
                          child: Container(
                            margin: const EdgeInsets.all(12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildHeaderSectionSimple(),
                                  const SizedBox(height: 16),
                                  _buildSimpleGrid(provider),
                                  const Divider(height: 32),
                                  _buildStatusToggles(),
                                  const SizedBox(height: 12),
                                  const Text("F6: Save • ESC: Clear • TAB: Navigate",
                                      style: TextStyle(color: Colors.grey, fontSize: 10, fontStyle: FontStyle.italic)),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // SAVED MEDICINES & SEARCH PANEL (Right Side - 55%)
                        Expanded(
                          flex: 7,
                          child: Container(
                            margin: const EdgeInsets.only(top: 12, bottom: 12, right: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
                            ),
                            child: _buildRightSearchPanel(provider),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightSearchPanel(PharmacyProvider provider) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final recentList = provider.recentModifiedProducts;

    List<Product> searchMatches = [];
    if (query.isNotEmpty) {
      final rawMatches = provider.searchProducts(query, isSalesWindow: true);
      // Deduplicate by medicine name so each product appears EXACTLY ONCE (like Sales window)
      final Map<String, Product> uniqueMap = {};
      for (var p in rawMatches) {
        final key = p.name.trim().toLowerCase();
        if (!uniqueMap.containsKey(key)) {
          uniqueMap[key] = p;
        }
      }
      searchMatches = uniqueMap.values.toList();
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header
            Row(
              children: [
                const Icon(Icons.search_rounded, size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  "SEARCH SAVED MEDICINES",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Text(
                    "${provider.productMaster.length} ${provider.productMaster.length == 1 ? 'medicine' : 'medicines'}",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Search input field
            Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent && searchMatches.isNotEmpty) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    setState(() {
                      _highlightedSearchIndex = (_highlightedSearchIndex + 1) % searchMatches.length;
                    });
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    setState(() {
                      _highlightedSearchIndex =
                          (_highlightedSearchIndex - 1 + searchMatches.length) % searchMatches.length;
                    });
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                    if (_highlightedSearchIndex >= 0 &&
                        _highlightedSearchIndex < searchMatches.length) {
                      final p = searchMatches[_highlightedSearchIndex];
                      _selectProduct(p);
                      provider.trackProductModified(p);
                      _searchCtrl.clear();
                      _highlightedSearchIndex = 0;
                    }
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                    setState(() {
                      _searchCtrl.clear();
                      _highlightedSearchIndex = 0;
                    });
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _searchFocus.hasFocus ? Colors.blue : Colors.grey.shade300,
                    width: _searchFocus.hasFocus ? 1.5 : 1,
                  ),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: (val) {
                    setState(() {
                      _highlightedSearchIndex = 0;
                    });
                  },
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: "Search by name, ID, generic, rack, HSN, barcode...",
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                            onPressed: () {
                              setState(() {
                                _searchCtrl.clear();
                                _highlightedSearchIndex = 0;
                              });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Currently editing alert bar
            if (_editingProduct != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.edit_note, size: 18, color: Colors.amber.shade900),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Currently Editing: ${_editingProduct!.name} (ID: ${_editingProduct!.id})",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: _clear,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: const Text(
                          "+ New Medicine",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // SECTION HEADER FOR LAST MODIFIED STOCKS (RECENT 20)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 16, color: Colors.indigo.shade800),
                  const SizedBox(width: 6),
                  Text(
                    "LAST MODIFIED STOCKS (RECENT 20)",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Text(
                      "${recentList.length} recent",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // MAIN LIST UNDER SEARCH BOX (LAST MODIFIED STOCKS - MAX 20)
            Expanded(
              child: recentList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            "No last modified stocks history",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Registered or edited products will automatically appear here.",
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: recentList.length,
                      separatorBuilder: (ctx, i) => const SizedBox(height: 6),
                      itemBuilder: (ctx, index) {
                        final p = recentList[index];
                        final isSelected = _editingProduct?.id == p.id;

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.blue.shade50.withValues(alpha: 0.7)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? Colors.blue : Colors.grey.shade200,
                              width: isSelected ? 1.5 : 1,
                            ),
                            boxShadow: isSelected
                                ? [BoxShadow(color: Colors.blue.withValues(alpha: 0.1), blurRadius: 4)]
                                : null,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Tooltip(
                                message: "Edit ${p.name}",
                                child: InkWell(
                                  onTap: () {
                                    _selectProduct(p);
                                    provider.trackProductModified(p);
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.blue : Colors.blue.shade50,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected ? Colors.blue : Colors.blue.shade200,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.edit,
                                      color: isSelected ? Colors.white : Colors.blue.shade700,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            p.name,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected
                                                  ? Colors.blue.shade900
                                                  : Colors.black87,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (index == 0) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.teal.shade700,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              "LATEST EDITED",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (isSelected) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              "SELECTED",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (p.genericName.isNotEmpty) ...[
                                          Text(
                                            p.genericName,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Text(
                                          "ID: ${p.id}",
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade500,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (p.rack.isNotEmpty)
                                          _badge("Rack: ${p.rack}", Colors.teal),
                                        _badge(p.category, Colors.indigo),
                                        _badge("Pack: ${p.packSize}", Colors.blueGrey),
                                        if (p.hsnCode.isNotEmpty)
                                          _badge("HSN: ${p.hsnCode}", Colors.grey),
                                        _badge("GST: ${p.gstPercent.toInt()}%", Colors.deepOrange),
                                        if (p.batch.isNotEmpty)
                                          _badge("SKU: ${p.batch}", Colors.purple),
                                        if (!p.isActive) _badge("INACTIVE", Colors.red),
                                        if (p.isControlled) _badge("CONTROLLED", Colors.orange),
                                        if (p.isNrx) _badge("NRX", Colors.pink),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: isSelected ? Colors.blue : Colors.grey.shade300,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),

        // SEPARATE SEARCH DROPDOWN OVERLAY (WHEN SEARCHING)
        if (query.isNotEmpty)
          Positioned(
            top: 76, // Positioned right below search textfield
            left: 0,
            right: 0,
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(8),
              shadowColor: Colors.black45,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 340),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade600, width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search dropdown header bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade800,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.manage_search_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            "SEARCH RESULTS (${searchMatches.length})",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            "Priority: Stock Qty > Sales > Name",
                            style: TextStyle(color: Colors.white70, fontSize: 10, fontStyle: FontStyle.italic),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              setState(() {
                                _searchCtrl.clear();
                                _highlightedSearchIndex = 0;
                              });
                            },
                            child: const Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ],
                      ),
                    ),

                    // List of matching items with Sales Window priority
                    Flexible(
                      child: searchMatches.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                "No medicines found matching '$query'",
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.all(6),
                              itemCount: searchMatches.length,
                              separatorBuilder: (ctx, i) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
                              itemBuilder: (ctx, index) {
                                final p = searchMatches[index];
                                final isHighlighted = index == _highlightedSearchIndex;

                                return InkWell(
                                  onTap: () {
                                    _selectProduct(p);
                                    provider.trackProductModified(p);
                                    setState(() {
                                      _searchCtrl.clear();
                                      _highlightedSearchIndex = 0;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isHighlighted
                                          ? Colors.blue.shade50
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: isHighlighted
                                          ? Border.all(color: Colors.blue.shade300)
                                          : null,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 26,
                                          height: 26,
                                          decoration: BoxDecoration(
                                            color: isHighlighted ? Colors.blue : Colors.grey.shade100,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              "${index + 1}",
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: isHighlighted ? Colors.white : Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      p.name,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.bold,
                                                        color: isHighlighted
                                                            ? Colors.blue.shade900
                                                            : Colors.black87,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (p.stock > 0)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.teal.shade50,
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: Colors.teal.shade200),
                                                      ),
                                                      child: Text(
                                                        "Stock: ${p.stock}",
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.teal.shade800,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  if (p.genericName.isNotEmpty)
                                                    Text(
                                                      p.genericName,
                                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                                    ),
                                                  const Spacer(),
                                                  Text(
                                                    "ID: ${p.id}  •  Rack: ${p.rack.isNotEmpty ? p.rack : 'N/A'}",
                                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
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
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _badge(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color.shade800),
      ),
    );
  }

  Widget _buildToolbar(PharmacyProvider provider, {bool isCompact = false}) {
    final c = AppColors.of(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _toolbarButton(Icons.add_circle_outline, "NEW", Colors.blue, onTap: _clear),
          const SizedBox(width: 8),
          _toolbarButton(Icons.save_outlined, "SAVE (F6)", Colors.green, onTap: _save),
          const SizedBox(width: 8),
          _toolbarButton(Icons.copy_outlined, "DUPLICATE", Colors.orange, onTap: () {
            if (_nameCtrl.text.isNotEmpty) {
              setState(() {
                _editingProduct = null;
                _generatedId = _generate10DigitId();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Product cloned! Press SAVE to create new entry."), backgroundColor: Colors.orange)
              );
            }
          }),
          const SizedBox(width: 8),
          _toolbarButton(Icons.delete_outline, "DELETE", Colors.red, onTap: () {
            if (_editingProduct != null) {
              provider.deleteProduct(_editingProduct!.id);
              _clear();
            }
          }),
          if (!isCompact) ...[
            const SizedBox(width: 8),
            _toolbarButton(Icons.call_merge_rounded, "MERGE", Colors.deepPurple, onTap: () {
              Provider.of<AppProvider>(context, listen: false).openProductMerge();
            }),
            const Spacer(),
            _toolbarButton(Icons.upload_file_outlined, "IMPORT MASTER", Colors.indigo, onTap: () {
              Provider.of<AppProvider>(context, listen: false).openStockManagement();
            }, isPrimary: true),
          ],
          if (isCompact) ...[
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey),
              onPressed: () => Navigator.pop(context),
              tooltip: "Close",
            ),
          ],
        ],
      ),
    );
  }

  Widget _toolbarButton(IconData icon, String label, Color color, {VoidCallback? onTap, bool isPrimary = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isPrimary ? color : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isPrimary ? color : Colors.grey.shade300),
          boxShadow: isPrimary ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2))] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isPrimary ? Colors.white : color, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isPrimary ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSectionSimple() {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final enteredName = _nameCtrl.text.trim().toLowerCase();
    bool isDuplicateName = false;
    if (enteredName.isNotEmpty) {
      if (_editingProduct == null) {
        isDuplicateName = provider.productMaster.any((p) => p.name.trim().toLowerCase() == enteredName) ||
            provider.products.any((p) => p.name.trim().toLowerCase() == enteredName);
      } else {
        isDuplicateName = provider.productMaster.any((p) => p.id != _editingProduct!.id && p.name.trim().toLowerCase() == enteredName) ||
            provider.products.any((p) => p.id != _editingProduct!.id && p.name.trim().toLowerCase() == enteredName);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text("MEDICINE NAME *", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blue.shade800, letterSpacing: 1.2)),
                      if (isDuplicateName) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: const Text(
                            "DUPLICATE WARNING",
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 35,
                    decoration: BoxDecoration(
                      color: isDuplicateName ? Colors.red.shade50.withValues(alpha: 0.5) : Colors.blue.shade50.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDuplicateName ? Colors.red : (_nameFocus.hasFocus ? Colors.blue : Colors.blue.shade100),
                        width: isDuplicateName ? 1.5 : (_nameFocus.hasFocus ? 1.5 : 1),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _nameCtrl,
                      focusNode: _nameFocus,
                      onChanged: (v) => setState(() {}),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: isDuplicateName ? Colors.red.shade900 : Colors.blue.shade900,
                      ),
                      decoration: InputDecoration(
                        hintText: "ENTER MEDICINE NAME",
                        hintStyle: TextStyle(color: Colors.blue.shade200, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("PRODUCT ID", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.blueGrey.shade300)),
                  const SizedBox(height: 4),
                  Container(
                    height: 35,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(_editingProduct != null ? _editingProduct!.id : _generatedId,
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.blue.shade700),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (isDuplicateName) ...[
          const SizedBox(height: 4),
          const Text(
            "⚠️ A medicine with this exact name already exists. Saving will be blocked.",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusToggles() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _simpleCheck("Controlled", _isControlled, (v) => setState(() => _isControlled = v!)),
        _simpleCheck("Banned", _isBanned, (v) => setState(() => _isBanned = v!)),
        _simpleCheck("NRX", _isNrx, (v) => setState(() => _isNrx = v!)),
        _simpleCheck("Active", _isActive, (v) => setState(() => _isActive = v!)),
      ],
    );
  }

  Widget _buildSimpleGrid(PharmacyProvider provider) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _field("HSN CODE", _hsnCtrl, _hsnFocus, next: _rackFocus)),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: InkWell(
                onTap: () async {
                  final selected = await showDialog<String>(
                    context: context,
                    builder: (ctx) => const RackPickerDialog(),
                  );
                  if (selected != null) {
                    setState(() => _selectedRack = selected);
                  }
                },
                child: AbsorbPointer(
                  child: _field("RACK", TextEditingController(text: _selectedRack), _rackFocus),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _dropdown("CATEGORY", _selectedCategory, _getCategoryOptions(provider), (v) => setState(() => _selectedCategory = v ?? "Branded"), focus: _categoryFocus)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(flex: 2, child: _searchableGenericDropdown(provider)),
            const SizedBox(width: 8),
            Expanded(child: _searchableDropdown("PATENT", _selectedPatent, _getPatentOptions(provider), (v) => setState(() => _selectedPatent = v), focus: _patentFocus)),
            const SizedBox(width: 8),
            Expanded(child: _searchableDropdown("SCHEDULE", _selectedSchedule, ["Select", "H", "H1", "G", "X", "Narcotic"], (v) => setState(() => _selectedSchedule = v), focus: _scheduleFocus)),
          ],
        ),
        const SizedBox(height: 12),
        const Align(alignment: Alignment.centerLeft, child: Text("STOCK & TAXATION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.start,
          children: [
            SizedBox(width: 75, child: _field("REORDER", _reorderCtrl, _reorderFocus)),
            SizedBox(width: 75, child: _field("MAX LVL", _maxCtrl, _maxFocus)),
            SizedBox(width: 75, child: _field("PACKING", _packingCtrl, _packingFocus)),
            SizedBox(width: 75, child: _field("LEAD TIME", _leadTimeCtrl, _leadTimeFocus)),
            SizedBox(width: 75, child: _dropdown("GST %", _selectedGst, ["0", "5", "12", "18"], (v) => setState(() => _selectedGst = v!), focus: _gstFocus)),
            SizedBox(width: 75, child: _field("DISC %", _discCtrl, _discFocus)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("LOCK DISC %", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade600)),
                const SizedBox(height: 4),
                Container(
                  height: 32,
                  width: 32,
                  alignment: Alignment.centerLeft,
                  child: Checkbox(
                    value: _isDiscLocked,
                    onChanged: (v) => setState(() => _isDiscLocked = v!),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _field("BARCODE / SKU", _barcodeCtrl, _barcodeFocus)),
            const SizedBox(width: 8),
            Expanded(child: _field("SHORTCODE / ALIAS", _aliasCtrl, _aliasFocus)),
          ],
        ),
        const SizedBox(height: 8),
        _searchableDropdown("PREFERRED WHOLESALE", _selectedWholesale, ["Select Wholesale", ...provider.suppliers], (v) => setState(() => _selectedWholesale = v)),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, FocusNode node, {FocusNode? next, Function(String)? onChange, bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade600)),
        const SizedBox(height: 4),
        Container(
          height: 32,
          decoration: BoxDecoration(
            color: enabled ? Colors.white : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: node.hasFocus ? Colors.blue : Colors.grey.shade300,
              width: node.hasFocus ? 1.5 : 1,
            ),
          ),
          child: TextField(
            controller: ctrl,
            focusNode: node,
            enabled: enabled,
            onChanged: onChange,
            onSubmitted: (_) => next?.requestFocus(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _searchableGenericDropdown(PharmacyProvider provider) {
    final List<String> allGenerics = provider.generics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "GENERIC NAME",
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade600),
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            return RawAutocomplete<String>(
              textEditingController: _genericCtrl,
              focusNode: _genericFocus,
              optionsBuilder: (TextEditingValue textEditingValue) {
                final text = textEditingValue.text.trim().toLowerCase();
                if (text.isEmpty || text == "select generic") {
                  return allGenerics.take(50);
                }
                final matches = allGenerics.where((g) => g.toLowerCase().contains(text)).toList();
                return matches.take(50);
              },
              onSelected: (String selection) {
                setState(() {
                  _selectedGeneric = selection;
                  _genericCtrl.text = selection;
                });
                _patentFocus.requestFocus();
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: focusNode.hasFocus ? Colors.blue : Colors.grey.shade300,
                      width: focusNode.hasFocus ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: "Select Generic",
                            hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _selectedGeneric = val.trim().isEmpty ? "Select Generic" : val.trim();
                            });
                          },
                          onSubmitted: (_) {
                            _patentFocus.requestFocus();
                          },
                        ),
                      ),
                      if (controller.text.isNotEmpty)
                        InkWell(
                          onTap: () {
                            controller.clear();
                            setState(() {
                              _selectedGeneric = "Select Generic";
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.close, size: 14, color: Colors.grey.shade600),
                          ),
                        ),
                      Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                    ],
                  ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 6.0,
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.white,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      width: constraints.maxWidth,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade100),
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          final isHighlighted = AutocompleteHighlightedOption.of(context) == index;
                          return InkWell(
                            onTap: () => onSelected(option),
                            child: Container(
                              color: isHighlighted ? Colors.blue.shade50 : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Text(
                                option,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w600,
                                  color: isHighlighted ? Colors.blue.shade900 : Colors.black87,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _searchableDropdown(String label, String val, List<String> items, Function(String) onChange, {FocusNode? focus}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade600)),
        const SizedBox(height: 4),
        InkWell(
          focusNode: focus,
          onTap: () async {
            String? selected = await showDialog<String>(
              context: context,
              builder: (ctx) => _SearchablePickerOverlay(title: label, items: items, currentValue: val),
            );
            if (selected != null) {
              onChange(selected);
            }
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: focus?.hasFocus == true ? Colors.blue : Colors.grey.shade300,
                width: focus?.hasFocus == true ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    val,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: Colors.grey.shade600, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdown(String label, String val, List<String> items, Function(String?) onChange, {FocusNode? focus}) {
    final uniqueItems = items.toSet().toList();
    if (!uniqueItems.contains(val)) {
      uniqueItems.insert(0, val);
    }
    final safeVal = uniqueItems.contains(val) ? val : (uniqueItems.isNotEmpty ? uniqueItems.first : val);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade600)),
        const SizedBox(height: 4),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: focus?.hasFocus == true ? Colors.blue : Colors.grey.shade300,
              width: focus?.hasFocus == true ? 1.5 : 1,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: safeVal,
              isDense: true,
              isExpanded: true,
              focusNode: focus,
              items: uniqueItems.map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  )
              )).toList(),
              onChanged: onChange,
            ),
          ),
        ),
      ],
    );
  }

  Widget _simpleCheck(String label, bool val, Function(bool?) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(value: val, onChanged: onChanged, visualDensity: VisualDensity.compact),
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 20),
      ],
    );
  }
}

class RackPickerDialog extends StatefulWidget {
  const RackPickerDialog({super.key});

  @override
  State<RackPickerDialog> createState() => _RackPickerDialogState();
}

class _RackPickerDialogState extends State<RackPickerDialog> {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PharmacyProvider>(context);
    final racks = provider.racks;

    Set<String> rowLabels = {};
    int maxCol = 10;
    for (var r in racks) {
      final match = RegExp(r'^([A-Z]*)(\d+)$').firstMatch(r);
      if (match != null) {
        String row = match.group(1) ?? "";
        if (row.isEmpty) row = "#";
        rowLabels.add(row);
        int col = int.tryParse(match.group(2)!) ?? 0;
        if (col > maxCol) maxCol = col;
      }
    }
    if (rowLabels.isEmpty) rowLabels.addAll(["A", "B", "C", "D", "E"]);
    List<String> sortedRows = rowLabels.toList()..sort((a, b) {
      if (a == "#") return -1;
      if (b == "#") return 1;
      return a.compareTo(b);
    });
    maxCol += 1;
    if (maxCol < 15) maxCol = 15;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.grid_view, color: Colors.blue),
          const SizedBox(width: 10),
          const Text("Select Rack Location", style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ],
      ),
      contentPadding: EdgeInsets.zero,
      content: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.7,
        color: Colors.grey.shade50,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 40 + (maxCol * 60.0),
                  child: Column(
                    children: [
                      Container(
                        height: 30,
                        color: const Color(0xFF4A4A4A),
                        child: Row(
                          children: [
                            Container(width: 40, alignment: Alignment.center, child: const Text("R/C", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                            ...List.generate(maxCol, (i) => SizedBox(width: 60, child: Center(child: Text("${i + 1}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))))),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: sortedRows.length,
                          itemBuilder: (context, rowIndex) {
                            String rowLabel = sortedRows[rowIndex];
                            return Container(
                              height: 45,
                              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    color: Colors.grey.shade200,
                                    alignment: Alignment.center,
                                    child: Text(rowLabel, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                  ),
                                  ...List.generate(maxCol, (colIndex) {
                                    int colNum = colIndex + 1;
                                    String rackName = (rowLabel == "#" ? "" : rowLabel) + colNum.toString();
                                    bool exists = racks.contains(rackName);
                                    bool isActive = provider.isRackActive(rackName);

                                    return InkWell(
                                      onTap: () {
                                        Navigator.pop(context, rackName);
                                      },
                                      child: Container(
                                        width: 56,
                                        margin: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: exists ? (isActive ? Colors.green.shade500 : Colors.blueGrey.shade300) : Colors.red.shade100.withValues(alpha: 0.3),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: exists ? Colors.green.shade700 : Colors.red.shade200.withValues(alpha: 0.5)),
                                        ),
                                        child: Center(
                                          child: Text(
                                            rackName,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: exists ? FontWeight.bold : FontWeight.normal,
                                              color: exists ? Colors.white : Colors.red.shade900.withValues(alpha: 0.5),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white,
              child: Row(
                children: [
                  _legendItem(Colors.green, "Active Rack"),
                  const SizedBox(width: 20),
                  _legendItem(Colors.blueGrey.shade300, "Inactive Rack"),
                  const SizedBox(width: 20),
                  _legendItem(Colors.red.shade100, "Available Slot"),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) => Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 11))]);
}

class _SearchablePickerOverlay extends StatefulWidget {
  final String title;
  final List<String> items;
  final String currentValue;

  const _SearchablePickerOverlay({
    required this.title,
    required this.items,
    required this.currentValue,
  });

  @override
  State<_SearchablePickerOverlay> createState() => _SearchablePickerOverlayState();
}

class _SearchablePickerOverlayState extends State<_SearchablePickerOverlay> {
  late TextEditingController _searchCtrl;
  late List<String> _filteredItems;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _filteredItems = widget.items.toSet().toList();
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items.toSet().toList();
      } else {
        _filteredItems = widget.items.where((i) => i.toLowerCase().contains(query)).toSet().toList();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 380,
        height: 420,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "Search ${widget.title}...",
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _searchCtrl.clear()),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                  child: const Text("Clear", style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.separated(
                  itemCount: _filteredItems.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                  itemBuilder: (ctx, i) {
                    final item = _filteredItems[i];
                    final bool isSelected = item == widget.currentValue;
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        color: isSelected ? Colors.blue.shade50 : null,
                        child: Text(
                          item,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? Colors.blue.shade900 : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.bottomLeft,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("x Close", style: TextStyle(color: Colors.black54, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
