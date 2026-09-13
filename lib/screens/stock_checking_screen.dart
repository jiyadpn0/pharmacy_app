import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/mdi_controller.dart';
import '../utils/theme_constants.dart';
import '../widgets/pin_unlock_dialog.dart';
import '../widgets/app_date_picker.dart';
import '../utils/search_debouncer.dart';

enum StockViewMode { pendingOnly, discrepancies, twoSide }

class StockCheckingScreen extends StatefulWidget {
  const StockCheckingScreen({super.key});

  @override
  State<StockCheckingScreen> createState() => _StockCheckingScreenState();
}

class _StockCheckingScreenState extends State<StockCheckingScreen> {
  // UI State
  bool _batchMode = true;
  int _activeAgentIdx = 0;
  int _rightSideAgentIdx = 1;
  List<String> _agentNames = ["1"];
  StockViewMode _viewMode = StockViewMode.discrepancies;
  
  bool _enableExpiryFilter = false;
  DateTime? _expiryLimit;

  // Focus management
  final Map<int, Map<String, FocusNode>> _itemFocusNodesLeft = {};
  final Map<int, Map<String, FocusNode>> _itemFocusNodesRight = {};

  FocusNode _getFocusNode(int agentIdx, String key, bool isLeft) {
    final map = isLeft ? _itemFocusNodesLeft : _itemFocusNodesRight;
    map.putIfAbsent(agentIdx, () => {});
    return map[agentIdx]!.putIfAbsent(key, () => FocusNode());
  }

  // Draggable Column Widths
  final Map<String, double> _colWidths = {
    "series": 65,
    "name": 240,
    "packSize": 50,
    "batch": 100,
    "stock": 60,
    "physical": 85,
    "diff": 70,
    "expiry": 80,
    "checked": 60,
  };

  final Map<String, double> _adminColWidths = {
    "checked": 70,
    "sl": 40,
    "name": 280,
    "packSize": 60,
    "batch": 80,
    "series": 90,
    "stock": 80,
    "adjustment": 90,
    "final": 75,
    "expiry": 100,
    "lcostChange": 110,
  };

  // State Management
  final Map<int, Map<String, Map<String, dynamic>>> _agentFilters = {0: {}};
  final Map<int, Map<String, int?>> _agentPhysicalQtys = {0: {}};
  final Map<int, Set<String>> _agentCheckedIds = {0: {}};
  final Map<int, Set<String>> _agentConfirmedIds = {0: {}};

  List<dynamic> _pendingItems = [];
  List<dynamic> _pendingItemsRight = [];
  List<dynamic> _checkedItems = [];
  bool _isDataLoading = false;
  final Map<String, String> _nearestExpiryCache = {};
  final Map<String, _RackSortKey> _rackSortKeyCache = {};
  final Set<String> _syncedKeys = {};

  // Scroll Controllers for Desktop
  final ScrollController _leftScrollCtrl = ScrollController();
  final ScrollController _rightScrollCtrl = ScrollController();

  // Debounce for refresh and save
  final SearchDebouncer _refreshDebouncer = SearchDebouncer(milliseconds: 300);
  final SearchDebouncer _saveDebouncer = SearchDebouncer(milliseconds: 1000);

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _refreshDebouncer.dispose();
    _saveDebouncer.dispose();
    _leftScrollCtrl.dispose();
    _rightScrollCtrl.dispose();
    for (var map in [_itemFocusNodesLeft, _itemFocusNodesRight]) {
      for (var agentNodes in map.values) {
        for (var node in agentNodes.values) {
          node.dispose();
        }
      }
    }
    super.dispose();
  }

  // PART 6 FIX: Move heavy JSON saving to a background CPU core
  static String _encodeStateForSave(Map<String, dynamic> state) {
    return jsonEncode(state);
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final Map<String, dynamic> state = {
        'batchMode': _batchMode,
        'activeAgentIdx': _activeAgentIdx,
        'agentNames': _agentNames,
        'agentPhysicalQtys': _agentPhysicalQtys.map((k, v) => MapEntry(k.toString(), v)),
        'agentCheckedIds': _agentCheckedIds.map((k, v) => MapEntry(k.toString(), v.toList())),
        'agentConfirmedIds': _agentConfirmedIds.map((k, v) => MapEntry(k.toString(), v.toList())),
        'agentFilters': _agentFilters.map((k, v) => MapEntry(k.toString(), v)),
        'syncedKeys': _syncedKeys.toList(),
      };

      // Push the heavy encoding off the main UI thread so typing never lags
      final jsonString = await compute(_encodeStateForSave, state);
      await prefs.setString('stock_checking_progress', jsonString);
    } catch (e) {
      debugPrint("Error saving stock checking state: $e");
    }
  }

  Future<void> _loadState() async {
    setState(() => _isDataLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStr = prefs.getString('stock_checking_progress');

      if (savedStr != null) {
        final Map<String, dynamic> state = jsonDecode(savedStr);

        setState(() {
          _batchMode = state['batchMode'] ?? true;
          _activeAgentIdx = state['activeAgentIdx'] ?? 0;
          _agentNames = List<String>.from(state['agentNames'] ?? ["1"]);

          final savedQtys = state['agentPhysicalQtys'] as Map<String, dynamic>?;
          if (savedQtys != null) {
            _agentPhysicalQtys.clear();
            savedQtys.forEach((k, v) {
              final innerMap = (v as Map<String, dynamic>).map((ik, iv) => MapEntry(ik, iv as int?));
              _agentPhysicalQtys[int.parse(k)] = innerMap;
            });
          }

          final savedChecked = state['agentCheckedIds'] as Map<String, dynamic>?;
          if (savedChecked != null) {
            _agentCheckedIds.clear();
            savedChecked.forEach((k, v) {
              _agentCheckedIds[int.parse(k)] = Set<String>.from(v as List);
            });
          }

          final savedConfirmed = state['agentConfirmedIds'] as Map<String, dynamic>?;
          if (savedConfirmed != null) {
            _agentConfirmedIds.clear();
            savedConfirmed.forEach((k, v) {
              _agentConfirmedIds[int.parse(k)] = Set<String>.from(v as List);
            });
          }

          final savedFilters = state['agentFilters'] as Map<String, dynamic>?;
          if (savedFilters != null) {
            _agentFilters.clear();
            savedFilters.forEach((k, v) {
              _agentFilters[int.parse(k)] = (v as Map<String, dynamic>).map((fk, fv) => MapEntry(fk, fv as Map<String, dynamic>));
            });
          }

          final savedSynced = state['syncedKeys'] as List?;
          if (savedSynced != null) {
            _syncedKeys.clear();
            _syncedKeys.addAll(List<String>.from(savedSynced));
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading stock checking state: $e");
    } finally {
      _refreshData();
    }
  }

  void _scheduleRefresh({bool immediate = false}) {
    if (immediate) {
      _refreshData();
    } else {
      _refreshDebouncer.run(_refreshData);
    }
  }

  void _scheduleSave() {
    _saveDebouncer.run(() => _saveState());
  }

  // PART 4 FIX: The Memory Sweeper
  void _cleanupFocusNodes(List<dynamic> pending, List<dynamic> pendingRight, List<dynamic> checked) {
    final validKeys = <String>{};
    for (var list in [pending, pendingRight, checked]) {
      for (var p in list) {
        validKeys.add(_batchMode ? "${p.id}|${p.batch}" : p.id);
      }
    }

    for (var map in [_itemFocusNodesLeft, _itemFocusNodesRight]) {
      for (var agentNodes in map.values) {
        agentNodes.removeWhere((key, node) {
          if (!validKeys.contains(key)) {
            node.dispose(); // Kills the unused memory node
            return true;
          }
          return false;
        });
      }
    }
  }

  void _refreshData() async { 
    if (!mounted) return;
    setState(() => _isDataLoading = true);

    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    List<dynamic> rawItems = _batchMode ? pharma.products : pharma.productMaster;

    if (!_batchMode && _nearestExpiryCache.isEmpty) {
      for (var p in pharma.products) {
        if (p.stock <= 0) continue;
        final current = _nearestExpiryCache[p.id];
        if (current == null) {
          _nearestExpiryCache[p.id] = p.expiry;
        } else {
          final d1 = _parseExpiry(p.expiry) ?? DateTime(2999);
          final d2 = _parseExpiry(current) ?? DateTime(2999);
          if (d1.isBefore(d2)) {
            _nearestExpiryCache[p.id] = p.expiry;
          }
        }
      }
    }

    final pending = <dynamic>[];
    final pendingRight = <dynamic>[];
    final checked = <dynamic>[];
    final currentFiltersLeft = _agentFilters[_activeAgentIdx] ?? {};
    final rightAgentIdx = (_viewMode == StockViewMode.twoSide && _agentNames.length > 1) ? _rightSideAgentIdx : -1;
    final Map<String, Map<String, dynamic>> currentFiltersRight = rightAgentIdx != -1 ? (_agentFilters[rightAgentIdx] ?? {}) : {};

    for (var p in rawItems) {
      if (p.stock <= 0) continue;

      String key = _batchMode ? "${p.id}|${p.batch}" : p.id;
      if (_syncedKeys.contains(key)) continue;

      bool matchesLeft = _checkProductMatches(p, currentFiltersLeft, pharma.products);
      bool matchesRight = rightAgentIdx != -1 ? _checkProductMatches(p, currentFiltersRight, pharma.products) : matchesLeft;

      if (matchesLeft || matchesRight) {
        if (_viewMode == StockViewMode.twoSide && rightAgentIdx != -1) {
          if (matchesLeft) pending.add(p);
          if (matchesRight) pendingRight.add(p);
        } else if (_viewMode == StockViewMode.discrepancies) {
          if (matchesLeft) {
            pending.add(p);
            if (_agentCheckedIds[_activeAgentIdx]!.contains(key)) {
              checked.add(p);
            }
          }
        } else {
          bool isConfirmedLeft = _agentConfirmedIds[_activeAgentIdx]!.contains(key);
          if (matchesLeft && !isConfirmedLeft) {
            pending.add(p);
          }
        }
      }
    }

    pending.sort((a, b) => _compareRacks(a.rack, b.rack));
    pendingRight.sort((a, b) => _compareRacks(a.rack, b.rack));
    checked.sort((a, b) => _compareRacks(a.rack, b.rack));

    // PART 4 FIX: Trigger the memory cleanup before refreshing the screen
    _cleanupFocusNodes(pending, pendingRight, checked);

    if (!mounted) return; 

    setState(() {
      _pendingItems = pending;
      _pendingItemsRight = pendingRight;
      _checkedItems = checked;
      _isDataLoading = false;
    });
  }

  static final RegExp _rackRe = RegExp(r'^([A-Z]*)([\d.]*)$');

  _RackSortKey _getRackSortKey(String? r) {
    final String s = r?.trim().toUpperCase() ?? "";
    return _rackSortKeyCache.putIfAbsent(s, () {
      var m = _rackRe.firstMatch(s);
      if (m == null) return _RackSortKey(s, 0, s.length);
      String alpha = m.group(1) ?? "";
      String nStr = m.group(2) ?? "";
      return _RackSortKey(alpha, double.tryParse(nStr) ?? 0.0, nStr.length);
    });
  }

  int _compareRacks(String? r1, String? r2) {
    if (r1 == r2) return 0;
    if ((r1 == null || r1.isEmpty) && (r2 == null || r2.isEmpty)) return 0;
    if (r1 == null || r1.isEmpty) return 1;
    if (r2 == null || r2.isEmpty) return -1;

    final k1 = _getRackSortKey(r1);
    final k2 = _getRackSortKey(r2);

    int aComp = k1.alpha.compareTo(k2.alpha);
    if (aComp != 0) return aComp;

    if (k1.numeric != k2.numeric) return k1.numeric.compareTo(k2.numeric);
    return k1.length.compareTo(k2.length);
  }

  bool _checkProductMatches(dynamic p, Map<String, Map<String, dynamic>> filters, List<Product> allBatches) {
    if (filters.isEmpty) return true;

    for (var entry in filters.entries) {
      final colKey = entry.key;
      final filter = entry.value;
      final val = _getColValue(p, colKey, allBatches);

      if (filter['mode'] == 'values') {
        List<String> allowed = List<String>.from(filter['selected_values'] ?? []);
        if (!allowed.contains(val?.toString() ?? "")) return false;
      } else {
        String? condition = filter['condition'];
        if (condition != null && condition != 'Clear' && condition != 'None') {
          if (filter['type'] == ColumnType.text) {
            String cellStr = (val?.toString() ?? "").toLowerCase();
            String filterStr = (filter['value1']?.toString() ?? "").toLowerCase();
            if (condition == 'Equals' && cellStr != filterStr) {
              return false;
            } else if (condition == 'Contains' && !cellStr.contains(filterStr)) return false;
            else if (condition == 'Begins With' && !cellStr.startsWith(filterStr)) return false;
          } else if (filter['type'] == ColumnType.numeric) {
            double cellNum = double.tryParse(val?.toString() ?? "0") ?? 0.0;
            double v1 = double.tryParse(filter['value1']?.toString() ?? "0") ?? 0.0;
            if (condition == 'Equals' && cellNum != v1) {
              return false;
            } else if (condition == 'Greater Than' && cellNum <= v1) return false;
            else if (condition == 'Less Than' && cellNum >= v1) return false;
            else if (condition == 'Between') {
              double v2 = double.tryParse(filter['value2']?.toString() ?? "0") ?? 0.0;
              if (cellNum < v1 || cellNum > v2) return false;
            }
          }
        }
      }
    }
    return true;
  }

  dynamic _getColValue(dynamic p, String key, List<Product> allBatches) {
    if (key == 'name') return p.name;
    if (key == 'series') return p.rack;
    if (key == 'packSize') {
      return p.packSize;
    }
    if (key == 'stock') return p.stock;
    if (key == 'batch') return p.batch;
    if (key == 'expiry') {
      if (_batchMode) return p.expiry;
      return _nearestExpiryCache[p.id] ?? p.expiry;
    }
    return null;
  }

  DateTime? _parseExpiry(String expiry) {
    if (expiry.isEmpty) return null;
    try {
      if (expiry.contains('/')) {
        final pts = expiry.split('/');
        int month = int.parse(pts[0]);
        int year = 2000 + int.parse(pts[1]);
        return DateTime(year, month, 1);
      }
    } catch (_) {}
    return null;
  }

  bool _isNearExpiry(String expiry) {
    if (!_enableExpiryFilter || _expiryLimit == null) return false;
    final date = _parseExpiry(expiry);
    if (date == null) return false;
    return !date.isAfter(_expiryLimit!);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        bool hasChanges = false;
        for (var map in _agentPhysicalQtys.values) {
          if (map.isNotEmpty) {
            hasChanges = true;
            break;
          }
        }

        final pharma = Provider.of<PharmacyProvider>(context, listen: false);
        final totalStockItems = (_batchMode ? pharma.products : pharma.productMaster).where((p) => p.stock > 0).length;
        bool missingChecks = false;
        for (int i = 0; i < _agentNames.length; i++) {
          if (_agentCheckedIds[i]!.length < totalStockItems) {
            missingChecks = true;
            break;
          }
        }

        if (missingChecks) {
          bool? exit = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                    title: const Text("Unfinished Stock Check"),
                    content: const Text("Some items have not been physically counted. Are you sure you want to close without finishing?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("KEEP CHECKING")),
                      ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          child: const Text("EXIT ANYWAY")),
                    ],
                  ));
          if (exit == true) {
            if (context.mounted) Navigator.of(context).pop();
          }
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.of(context).background,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToolbar(),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildListArea(isPending: true)),
                  if (_viewMode != StockViewMode.pendingOnly) ...[
                    const VerticalDivider(width: 1, thickness: 1),
                    Expanded(child: _buildListArea(isPending: false)),
                  ],
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  void _addAgent() async {
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    if (pharma.securityToggles['require_pin_add_agent_stock_check'] == true) {
      bool ok = await PinUnlockDialog.show(context, pharma,
          title: "Add Verification Agent", message: "Enter Master PIN to add a new stock checking agent.");
      if (!ok) return;
    }

    setState(() {
      int newIdx = _agentNames.length;
      _agentNames.add("${newIdx + 1}");
      _agentPhysicalQtys[newIdx] = {};
      _agentCheckedIds[newIdx] = {};
      _agentConfirmedIds[newIdx] = {};
      _agentFilters[newIdx] = {};
      _activeAgentIdx = newIdx;
    });
  }

  void _removeAgent(int idx) async {
    if (_agentNames.length <= 1) return;

    bool hasCounts = _agentPhysicalQtys[idx]?.isNotEmpty ?? false;
    bool confirm = true;

    if (hasCounts) {
      confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text("Remove Agent"),
                content: Text("Are you sure you want to remove ${_agentNames[idx]} and all their counts?"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text("REMOVE")),
                ],
              )) ?? false;
    }

    if (confirm) {
      setState(() {
        _agentNames.removeAt(idx);
        final newQtys = <int, Map<String, int?>>{};
        final newChecked = <int, Set<String>>{};
        final newConfirmed = <int, Set<String>>{};
        final newFilters = <int, Map<String, Map<String, dynamic>>>{};

        for (int i = 0; i < _agentNames.length; i++) {
          int oldIdx = i < idx ? i : i + 1;
          newQtys[i] = _agentPhysicalQtys[oldIdx] ?? {};
          newChecked[i] = _agentCheckedIds[oldIdx] ?? {};
          newConfirmed[i] = _agentConfirmedIds[oldIdx] ?? {};
          newFilters[i] = _agentFilters[oldIdx] ?? {};
        }

        _agentPhysicalQtys.clear();
        _agentPhysicalQtys.addAll(newQtys);
        _agentCheckedIds.clear();
        _agentCheckedIds.addAll(newChecked);
        _agentConfirmedIds.clear();
        _agentConfirmedIds.addAll(newConfirmed);
        _agentFilters.clear();
        _agentFilters.addAll(newFilters);

        if (_activeAgentIdx >= _agentNames.length) _activeAgentIdx = _agentNames.length - 1;
        if (_rightSideAgentIdx >= _agentNames.length) _rightSideAgentIdx = 0;
      });
      _scheduleRefresh(immediate: true);
    }
  }

  void _renameAgent(int idx) async {
    TextEditingController nameCtrl = TextEditingController(text: _agentNames[idx]);
    String? newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text("Rename Agent ${idx + 1}"),
              content: TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(labelText: "Agent Name")),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, nameCtrl.text), child: const Text("RENAME")),
              ],
            ));
    if (newName != null && newName.trim().isNotEmpty) {
      setState(() => _agentNames[idx] = newName.trim());
    }
  }

  void _showAdminAdjustmentDialog() async {
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    if (pharma.securityToggles['require_pin_admin_stock_adjustment'] == true) {
      bool ok = await PinUnlockDialog.show(context, pharma,
          title: "Adjustment (Admin) Access", message: "Enter Master PIN to access the consolidated adjustment window.");
      if (!ok) return;
    }

    final mdi = Provider.of<MdiController>(context, listen: false);
    mdi.openWindow(MdiWindow(
      id: "admin_adjustment",
      title: "ADJUSTMENT (ADMIN)",
      width: 1100,
      height: 700,
      content: AdminAdjustmentPanel(
        batchMode: _batchMode,
        agentNames: _agentNames,
        agentPhysicalQtys: _agentPhysicalQtys,
        onUpdatePhysical: (agentIdx, key, val) {
          setState(() {
            _agentPhysicalQtys.putIfAbsent(agentIdx, () => {});
            _agentPhysicalQtys[agentIdx]![key] = val;

            _agentCheckedIds.putIfAbsent(agentIdx, () => {});
            _agentConfirmedIds.putIfAbsent(agentIdx, () => {});

            if (val != null) {
              _agentCheckedIds[agentIdx]!.add(key);
              _agentConfirmedIds[agentIdx]!.add(key);
            } else {
              _agentCheckedIds[agentIdx]!.remove(key);
              _agentConfirmedIds[agentIdx]!.remove(key);
            }
          });
          _scheduleSave();
        },
        onResetItem: (key) {
          setState(() {
            for (int i = 0; i < _agentNames.length; i++) {
              _agentPhysicalQtys[i]?.remove(key);
              _agentCheckedIds[i]?.remove(key);
              _agentConfirmedIds[i]?.remove(key);
            }
            // Also reset Final count (stored at -1)
            _agentPhysicalQtys[-1]?.remove(key);
            _agentCheckedIds[-1]?.remove(key);
            _agentConfirmedIds[-1]?.remove(key);
          });
          _scheduleSave();
          _scheduleRefresh(immediate: true);
        },
        onMoveToChecked: (keys) {
          setState(() {
            _syncedKeys.addAll(keys);
            for (var key in keys) {
              for (int i = 0; i < _agentNames.length; i++) {
                _agentPhysicalQtys[i]?.remove(key);
                _agentCheckedIds[i]?.remove(key);
                _agentConfirmedIds[i]?.remove(key);
              }
              // Also clear from final adjustment entry
              _agentPhysicalQtys[-1]?.remove(key);
            }
          });
          _scheduleSave();
          _scheduleRefresh(immediate: true);
          mdi.closeWindow("admin_adjustment");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Adjusted items have been synced and removed from the list."),
              backgroundColor: Colors.indigo,
            ),
          );
        },
        onClose: () => mdi.closeWindow("admin_adjustment"),
        adminColWidths: _adminColWidths,
        onResizeColumn: (key, w) => setState(() => _adminColWidths[key] = w.clamp(30.0, 1000.0)),
        enableExpiryFilter: _enableExpiryFilter,
        expiryLimit: _expiryLimit,
        rackCompareFn: _compareRacks,
      ),
    ));
  }

  Widget _buildToolbar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          _buildHeaderIcon(Icons.inventory_rounded, "Stock Checking", Colors.indigo),
          const SizedBox(width: 24),
          const Text("AGENT:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                ..._agentNames.asMap().entries.map((entry) {
                  int idx = entry.key;
                  String name = entry.value;
                  bool isActive = _activeAgentIdx == idx;
                  return GestureDetector(
                    onTap: () {
                      if (isActive) return;
                      setState(() => _activeAgentIdx = idx);
                      _scheduleRefresh(immediate: true);
                    },
                    onDoubleTap: () => _renameAgent(idx),
                    onSecondaryTap: () => _removeAgent(idx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.indigo : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Text(name,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isActive ? Colors.white : Colors.grey)),
                          if (isActive && _agentNames.length > 1) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _removeAgent(idx),
                              child: Icon(Icons.close, size: 12, color: isActive ? Colors.white70 : Colors.grey),
                            ),
                          ]
                        ],
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: () {
                    _addAgent();
                    _scheduleRefresh(immediate: true);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: const Icon(Icons.add, size: 14, color: Colors.grey),
                  ),
                ),
                const VerticalDivider(width: 16, indent: 4, endIndent: 4),
                GestureDetector(
                  onTap: _showAdminAdjustmentDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.red.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.shade100)),
                    child: Row(
                      children: [
                        Icon(Icons.admin_panel_settings_rounded, size: 12, color: Colors.red.shade900),
                        const SizedBox(width: 6),
                        Text("ADJUSTMENT (ADMIN)",
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Row(
              children: [
                Checkbox(
                  value: _enableExpiryFilter,
                  onChanged: (v) {
                    setState(() => _enableExpiryFilter = v!);
                    _scheduleRefresh(immediate: true);
                  },
                  visualDensity: VisualDensity.compact,
                ),
                const Text("Expiry", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                if (_enableExpiryFilter) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      final d = await showAppDatePicker(
                        context: context,
                        initialDate: _expiryLimit ?? DateTime.now().add(const Duration(days: 90)),
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (d != null) {
                        setState(() => _expiryLimit = d);
                        _scheduleRefresh(immediate: true);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white, border: Border.all(color: Colors.blue.shade200), borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        _expiryLimit == null ? "Till Date" : DateFormat('MM/yy').format(_expiryLimit!),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (_viewMode == StockViewMode.twoSide) ...[
            const SizedBox(width: 8),
          ],
          const Spacer(),
          _buildViewModeToggle(),
          const SizedBox(width: 10),
          _buildModeToggle(),
        ],
      ),
    );
  }

  Widget _buildHeaderIcon(IconData icon, String title, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
      ],
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _modeButton("BATCH-WISE", _batchMode, () {
            setState(() => _batchMode = true);
            _scheduleRefresh(immediate: true);
          }),
          _modeButton("TOTAL QTY", !_batchMode, () {
            setState(() => _batchMode = false);
            _scheduleRefresh(immediate: true);
          }),
        ],
      ),
    );
  }

  Widget _buildViewModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _modeButton("CHANGES", _viewMode == StockViewMode.discrepancies, () {
            setState(() => _viewMode = StockViewMode.discrepancies);
            _scheduleRefresh(immediate: true);
          }),
          _modeButton("2-SIDE CHECK", _viewMode == StockViewMode.twoSide, () {
            setState(() {
              _viewMode = StockViewMode.twoSide;
              if (_rightSideAgentIdx >= _agentNames.length) {
                _rightSideAgentIdx = (_activeAgentIdx + 1) % _agentNames.length;
              }
            });
            _scheduleRefresh(immediate: true);
          }),
        ],
      ),
    );
  }

  Widget _modeButton(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isActive ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)] : null,
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isActive ? Colors.indigo : Colors.grey)),
      ),
    );
  }

  Widget _buildListArea({required bool isPending}) {
    if (_isDataLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isRightPanel = !isPending;
    final items = isPending ? _pendingItems : (_viewMode == StockViewMode.twoSide ? _pendingItemsRight : _checkedItems);
    final agentIdx = (isRightPanel && _viewMode == StockViewMode.twoSide && _agentNames.length > 1)
        ? _rightSideAgentIdx
        : _activeAgentIdx;

    final controller = isPending ? _leftScrollCtrl : _rightScrollCtrl;

    return Consumer<PharmacyProvider>(
      builder: (context, pharma, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Agent Dropdown on starting at above of the series
            if (!isRightPanel || _viewMode == StockViewMode.twoSide)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: agentIdx,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo),
                      items: _agentNames.asMap().entries.map((entry) {
                        return DropdownMenuItem<int>(
                          value: entry.key,
                          child: Text("Agent: ${entry.value}"),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            if (isPending) {
                              _activeAgentIdx = v;
                            } else {
                              _rightSideAgentIdx = v;
                            }
                          });
                          _scheduleRefresh(immediate: true);
                        }
                      },
                    ),
                  ),
                ),
              ),
            if (isRightPanel && _viewMode != StockViewMode.twoSide)
              const SizedBox(height: 36), // Maintain alignment even if hidden
            Expanded(
              child: Scrollbar(
                controller: controller,
                thumbVisibility: true,
                trackVisibility: true,
                child: SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: _getColumns().fold<double>(0.0, (sum, col) => sum + (_colWidths[col.key] ?? 0.0)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildListHeader(pharma, isPending, sideAgentIdx: agentIdx),
                        Expanded(
                          child: ListView.builder(
                            itemCount: items.length,
                            itemExtent: 64, // Must match row height for smooth navigation
                            itemBuilder: (context, index) {
                              final p = items[index];
                              String key = _batchMode ? "${p.id}|${p.batch}" : p.id;
                              String expStr = _batchMode ? p.expiry : (_nearestExpiryCache[p.id] ?? p.expiry);

                              return _StockItemRow(
                                key: ValueKey("${isPending ? 'L' : 'R'}_${agentIdx}_$key"),
                                p: p,
                                slNo: index + 1,
                                allBatches: pharma.products,
                                batchMode: _batchMode,
                                agentIdx: agentIdx,
                                colWidths: _colWidths,
                                physicalQty: _agentPhysicalQtys[agentIdx]?[key],
                                isChecked: _agentCheckedIds[agentIdx]?.contains(key) ?? false,
                                isConfirmed: _agentConfirmedIds[agentIdx]?.contains(key) ?? false,
                                expiryStr: expStr,
                                isNearExpiry: _isNearExpiry(expStr),
                                focusNode: _getFocusNode(agentIdx, key, isPending),
                                onQtyChanged: (val) {
                                  setState(() {
                                    _agentPhysicalQtys.putIfAbsent(agentIdx, () => {});
                                    _agentCheckedIds.putIfAbsent(agentIdx, () => {});

                                    // Explicitly allow 0 as a valid counted quantity
                                    _agentPhysicalQtys[agentIdx]![key] = val;

                                    if (val != null) {
                                      _agentCheckedIds[agentIdx]!.add(key);
                                    } else {
                                      _agentCheckedIds[agentIdx]!.remove(key);
                                      _agentConfirmedIds[agentIdx]?.remove(key);
                                    }
                                  });
                                  _scheduleSave();
                                  _scheduleRefresh();
                                },
                                onConfirmed: () {
                                  // Move focus to next row on Enter
                                  if (index < items.length - 1) {
                                    final nextItem = items[index + 1];
                                    String nextKey = _batchMode ? "${nextItem.id}|${nextItem.batch}" : nextItem.id;
                                    _getFocusNode(agentIdx, nextKey, isPending).requestFocus();
                                  }

                                  setState(() {
                                    _agentConfirmedIds.putIfAbsent(agentIdx, () => {});
                                    _agentConfirmedIds[agentIdx]!.add(key);
                                    // Also ensure it's in CheckedIds
                                    _agentCheckedIds.putIfAbsent(agentIdx, () => {});
                                    _agentCheckedIds[agentIdx]!.add(key);
                                  });
                                  
                                  if (_viewMode != StockViewMode.twoSide) {
                                    _scheduleRefresh(immediate: true); // Now jump to right side
                                  }
                                },
                                onCheckedToggle: () {
                                  setState(() {
                                    _agentCheckedIds.putIfAbsent(agentIdx, () => {});
                                    if (_agentCheckedIds[agentIdx]!.contains(key)) {
                                      _agentCheckedIds[agentIdx]!.remove(key);
                                    } else {
                                      _agentCheckedIds[agentIdx]!.add(key);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildListHeader(PharmacyProvider pharma, bool isPending, {int? sideAgentIdx}) {
    final cols = _getColumns();
    final targetAgentIdx = sideAgentIdx ?? _activeAgentIdx;
    final currentFilters = _agentFilters[targetAgentIdx] ?? {};

    return Container(
      color: Colors.grey.shade100,
      height: 52,
      child: Row(
        children: [
          ...cols.map((col) => _GridHeaderCell(
                  key: ValueKey("header_${targetAgentIdx}_${col.key}"),
                  col: col,
                  width: _colWidths[col.key] ?? 100,
                  currentFilter: currentFilters[col.key],
                  onResize: (newWidth) {
                    setState(() => _colWidths[col.key] = newWidth.clamp(30.0, 1000.0));
                  },
                    onQuickFilter: (condition, value) {
                      setState(() {
                        _agentFilters.putIfAbsent(targetAgentIdx, () => {});
                        if (condition == 'Clear') {
                          _agentFilters[targetAgentIdx]?.remove(col.key);
                        } else {
                          _agentFilters[targetAgentIdx]![col.key] = {
                            'mode': 'rules',
                            'type': col.type,
                            'condition': condition,
                            'value1': value,
                            'value2': '',
                          };
                        }
                      });
                      _scheduleRefresh(immediate: false);
                    },
                )),
        ],
      ),
    );
  }

  List<_ColInfo> _getColumns() {
    return [
      _ColInfo("series", "SERIES", align: TextAlign.center),
      _ColInfo("name", "PRODUCT", align: TextAlign.left),
      _ColInfo("packSize", "PACK", type: ColumnType.numeric, align: TextAlign.center),
      if (_batchMode) _ColInfo("batch", "BATCH", align: TextAlign.left),
      _ColInfo("stock", "SYSTEM", type: ColumnType.numeric, align: TextAlign.center),
      _ColInfo("physical", "PHYSICAL", type: ColumnType.numeric, align: TextAlign.center),
      _ColInfo("diff", "DIFF", align: TextAlign.center),
      _ColInfo("expiry", "EXPIRY", align: TextAlign.center),
      _ColInfo("checked", "CHECKED", align: TextAlign.center),
    ];
  }


  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          const Text("SUMMARY:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 16),
          _summaryBadge("Checked: ${_agentCheckedIds[_activeAgentIdx]!.length}", Colors.indigo),
          const Spacer(),
          Text(
            "Progress Saved Automatically",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade300, fontStyle: FontStyle.italic),
          ),
          const SizedBox(width: 24),
          _summaryBadge("Agent: ${_agentNames[_activeAgentIdx]}", Colors.grey),
        ],
      ),
    );
  }

  Widget _summaryBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }




}

// ============================================================================
// OPTIMIZED ITEM ROW WIDGET (STATEFUL FOR AGENT ISOLATION)
// ============================================================================
class _StockItemRow extends StatefulWidget {
  final dynamic p;
  final int slNo;
  final List<Product> allBatches;
  final bool batchMode;
  final int agentIdx;
  final Map<String, double> colWidths;
  final int? physicalQty;
  final bool isChecked;
  final bool isConfirmed;
  final String expiryStr;
  final bool isNearExpiry;
  final FocusNode? focusNode;
  final Function(int?) onQtyChanged;
  final VoidCallback onConfirmed;
  final VoidCallback onCheckedToggle;

  const _StockItemRow({
    super.key,
    required this.p,
    required this.slNo,
    required this.allBatches,
    required this.batchMode,
    required this.agentIdx,
    required this.colWidths,
    this.physicalQty,
    required this.isChecked,
    required this.isConfirmed,
    required this.expiryStr,
    required this.isNearExpiry,
    this.focusNode,
    required this.onQtyChanged,
    required this.onConfirmed,
    required this.onCheckedToggle,
  });

  @override
  State<_StockItemRow> createState() => _StockItemRowState();
}

class _StockItemRowState extends State<_StockItemRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.physicalQty?.toString() ?? "");
  }

  @override
  void didUpdateWidget(_StockItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Force reset if agent or product changed (even if value is the same)
    bool identityChanged = widget.agentIdx != oldWidget.agentIdx ||
                          widget.p.id != oldWidget.p.id ||
                          widget.batchMode != oldWidget.batchMode;

    final newVal = widget.physicalQty?.toString() ?? "";

    if (identityChanged || (_controller.text != newVal &&
        !(widget.physicalQty == null && _controller.text.isEmpty))) {
      _controller.text = newVal;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int systemQty = (widget.p.stock as num?)?.toInt() ?? 0;
    int? physicalQty = widget.physicalQty;
    int diff = (physicalQty ?? systemQty) - systemQty;

                                      final bool isH1 = widget.p.schedule.toUpperCase() == "H1";
                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => widget.focusNode?.requestFocus(),
                                        child: Container(
                                          height: 64,
                                          padding: const EdgeInsets.symmetric(horizontal: 0),
                                          decoration: BoxDecoration(
                                            color: widget.isChecked ? (isH1 ? Colors.red.withValues(alpha: 0.05) : Colors.green.withValues(alpha: 0.02)) : (isH1 ? Colors.red.withValues(alpha: 0.03) : Colors.white),
                                            border: const Border(bottom: BorderSide(color: Colors.grey, width: 0.2)),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Container(
                                                width: widget.colWidths["series"] ?? 65,
                                                alignment: Alignment.center,
                                                child: Text("${widget.p.rack ?? ""}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isH1 ? Colors.red.shade900 : Colors.blueGrey)),
                                              ),
                                              Container(
                                                width: widget.colWidths["name"] ?? 240,
                                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Text(widget.p.name ?? "-", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isH1 ? Colors.red.shade900 : Colors.black), overflow: TextOverflow.ellipsis),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                width: widget.colWidths["packSize"] ?? 50,
                                                alignment: Alignment.center,
                                                child: Text("${widget.p.packSize ?? 0}", style: TextStyle(fontSize: 12, color: isH1 ? Colors.red.shade700 : Colors.blueGrey)),
                                              ),
                                              if (widget.batchMode)
                                                Container(
                                                  width: widget.colWidths["batch"] ?? 100,
                                                  alignment: Alignment.centerLeft,
                                                  padding: const EdgeInsets.only(left: 8),
                                                  child: Text(widget.p.batch ?? "-", style: TextStyle(fontSize: 11, color: isH1 ? Colors.red.shade700 : Colors.blueGrey, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                                ),
                                              Container(
                                                width: widget.colWidths["stock"] ?? 60,
                                                alignment: Alignment.center,
                                                child: Text("$systemQty", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isH1 ? Colors.red.shade900 : Colors.blueGrey)),
                                              ),
                                              Container(
                                                width: widget.colWidths["physical"] ?? 85,
                                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                                alignment: Alignment.center,
                                                child: SizedBox(
                                                  height: 42,
                                                  child: TextField(
                                                    controller: _controller,
                                                    focusNode: widget.focusNode,
                                                    keyboardType: TextInputType.number,
                                                    textAlign: TextAlign.center,
                                                    textAlignVertical: TextAlignVertical.center,
                                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isH1 ? Colors.red.shade900 : Colors.black),
                                                    decoration: InputDecoration(
                                                      contentPadding: const EdgeInsets.only(bottom: 2),
                                                      isDense: true,
                                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: isH1 ? BorderSide(color: Colors.red.shade300) : const BorderSide(color: Colors.grey)),
                                                      focusedBorder: isH1 ? OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.red, width: 2)) : null,
                                                      fillColor: isH1 ? Colors.red.shade50 : Colors.white,
                                                      filled: true,
                                                      hintText: "-",
                                                    ),
                                                    onChanged: (v) {
                                                      int? val = int.tryParse(v);
                                                      widget.onQtyChanged(val);
                                                    },
                                                    onSubmitted: (v) => widget.onConfirmed(),
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                width: widget.colWidths["diff"] ?? 70,
                                                alignment: Alignment.center,
                                                child: (widget.physicalQty == null)
                                                    ? const Text("-", style: TextStyle(color: Colors.grey))
                                                    : _buildDiffIndicator(diff),
                                              ),
                                              Container(
                                                  width: widget.colWidths["expiry"] ?? 80,
                                                  alignment: Alignment.center,
                                                  child: Text(widget.expiryStr ?? "-",
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: widget.isNearExpiry ? Colors.red : (isH1 ? Colors.red.shade700 : Colors.blueGrey),
                                                          fontWeight: widget.isNearExpiry ? FontWeight.bold : FontWeight.normal))),
                                              Container(
                                                width: widget.colWidths["checked"] ?? 60,
                                                alignment: Alignment.center,
                                                child: _buildAttendanceMark(widget.physicalQty != null),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
  }

  Widget _buildAttendanceMark(bool attended) {
    if (!attended) return const SizedBox();
    return const Text("CHECKED",
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF4CAF50)));
  }

  Widget _buildDiffIndicator(int diff) {
    if (diff == 0) {
      return const Text("TALLY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue));
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center, // Center align diff indicator
      children: [
        Icon(diff > 0 ? Icons.add_circle : Icons.remove_circle, size: 12, color: diff > 0 ? Colors.green : Colors.red),
        const SizedBox(width: 4),
        Text("${diff.abs()}", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: diff > 0 ? Colors.green : Colors.red)),
      ],
    );
  }
}

class _RackSortKey {
  final String alpha;
  final double numeric;
  final int length;
  _RackSortKey(this.alpha, this.numeric, this.length);
}

// ============================================================================
// ADMIN ADJUSTMENT PANEL (FLOATING)
// ============================================================================
class AdminAdjustmentPanel extends StatefulWidget {
  final bool batchMode;
  final List<String> agentNames;
  final Map<int, Map<String, int?>> agentPhysicalQtys;
  final Function(int agentIdx, String key, int? val) onUpdatePhysical;
  final Function(String key) onResetItem;
  final Function(Set<String> keys) onMoveToChecked;
  final VoidCallback onClose;
  final Map<String, double> adminColWidths;
  final Function(String, double) onResizeColumn;
  final bool enableExpiryFilter;
  final DateTime? expiryLimit;
  final int Function(String?, String?)? rackCompareFn;

  const AdminAdjustmentPanel({
    super.key,
    required this.batchMode,
    required this.agentNames,
    required this.agentPhysicalQtys,
    required this.onUpdatePhysical,
    required this.onResetItem,
    required this.onMoveToChecked,
    required this.onClose,
    required this.adminColWidths,
    required this.onResizeColumn,
    required this.enableExpiryFilter,
    this.expiryLimit,
    this.rackCompareFn,
  });

  @override
  State<AdminAdjustmentPanel> createState() => _AdminAdjustmentPanelState();
}

class _AdminAdjustmentPanelState extends State<AdminAdjustmentPanel> {
  final Set<String> _selectedKeys = {};
  final Set<int> _verificationAgents = {};
  final Map<String, Map<String, dynamic>> _adminFilters = {};
  List<dynamic> _filteredItems = [];
  bool _isLoading = true;
  bool _allCheckableSelected = false;
  bool _showCheckedListOnly = false;
  final Map<String, FocusNode> _focusNodes = {};
  int _focusedIndex = -1;
  final ScrollController _adminScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // Default: select all agents for verification
    for (int i = 0; i < widget.agentNames.length; i++) {
      _verificationAgents.add(i);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _filterItems());
  }

  @override
  void didUpdateWidget(AdminAdjustmentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-filter if data or agent setup changed externally
    if (widget.agentPhysicalQtys != oldWidget.agentPhysicalQtys ||
        widget.agentNames.length != oldWidget.agentNames.length ||
        widget.batchMode != oldWidget.batchMode) {
      _filterItems();
    }
  }

  @override
  void dispose() {
    for (var node in _focusNodes.values) {
      node.dispose();
    }
    _adminScrollCtrl.dispose();
    super.dispose();
  }

  FocusNode _getFocusNode(String key) {
    return _focusNodes.putIfAbsent(key, () => FocusNode());
  }

  void _filterItems() {
    if (!mounted) return;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    
    List<dynamic> source;
    if (widget.batchMode) {
      source = pharma.products ?? [];
    } else {
      source = pharma.productMaster ?? [];
    }
    List<dynamic> allProducts = List.from(source);

    final compareFn = widget.rackCompareFn;

    if (compareFn != null) {
      allProducts.sort((a, b) => compareFn(a.rack, b.rack));
    }

    final items = allProducts.where((p) {
      if (p == null) return false;
      int stock = (p.stock as num?)?.toInt() ?? 0;
      if (stock <= 0) return false;
      
      String id = (p.id ?? "").toString();
      String batch = (p.batch ?? "").toString();
      String key = widget.batchMode ? "$id|$batch" : id;
      if (id.isEmpty) return false;

      bool attended = false;
      for (int i in _verificationAgents) {
        if (widget.agentPhysicalQtys[i]?[key] != null) {
          attended = true;
          break;
        }
      }
      if (!attended) return false;

      final finalQtys = widget.agentPhysicalQtys[-1];
      if (_showCheckedListOnly && (finalQtys == null || finalQtys[key] == null)) {
        return false;
      }

      bool matches = true;
      if (_adminFilters.isNotEmpty) {
        _adminFilters.forEach((colKey, filter) {
          final val = _getAdminColValue(p, colKey, source);
          String mode = filter['mode']?.toString() ?? "";
          if (mode == 'values') {
            List<String> allowed = [];
            if (filter['selected_values'] != null) {
              allowed = List<String>.from(filter['selected_values']);
            }
            if (!allowed.contains(val?.toString() ?? "")) matches = false;
          } else {
            String? condition = filter['condition']?.toString();
            if (condition != null && condition != 'Clear' && condition != 'None') {
              var type = filter['type'];
              if (type == ColumnType.text) {
                String cellStr = (val?.toString() ?? "").toLowerCase();
                String filterStr = (filter['value1']?.toString() ?? "").toLowerCase();
                if (condition == 'Equals' && cellStr != filterStr) {
                  matches = false;
                } else if (condition == 'Contains' && !cellStr.contains(filterStr)) {
                  matches = false;
                } else if (condition == 'Begins With' && !cellStr.startsWith(filterStr)) {
                  matches = false;
                }
              } else if (filter['type'] == ColumnType.numeric) {
                double cellNum = double.tryParse(val?.toString() ?? "0") ?? 0.0;
                double v1 = double.tryParse(filter['value1']?.toString() ?? "0") ?? 0.0;
                if (condition == 'Equals' && cellNum != v1) {
                  matches = false;
                } else if (condition == 'Greater Than' && cellNum <= v1) {
                  matches = false;
                } else if (condition == 'Less Than' && cellNum >= v1) {
                  matches = false;
                } else if (condition == 'Between') {
                  double v2 = double.tryParse(filter['value2']?.toString() ?? "0") ?? 0.0;
                  if (cellNum < v1 || cellNum > v2) {
                    matches = false;
                  }
                }
              }
            }
          }
        });
      }

      return matches;
    }).toList();

    // PART 4 FIX: Sweep unused memory nodes in the Admin Panel
    final validAdminKeys = items.map((p) {
      String id = (p.id ?? "").toString();
      String b = (p.batch ?? "").toString();
      return widget.batchMode ? "$id|$b" : id;
    }).toSet();
    
    _focusNodes.removeWhere((key, node) {
      if (!validAdminKeys.contains(key)) {
        node.dispose();
        return true;
      }
      return false;
    });

    setState(() {
      _filteredItems = items;
      if (_filteredItems.isEmpty) {
        _allCheckableSelected = false;
      } else {
        int checkableCount = 0;
        int selectedCount = 0;
        for (var p in _filteredItems) {
          if (p == null) continue;
          String id = (p.id ?? "").toString();
          String b = (p.batch ?? "").toString();
          String key = widget.batchMode ? "$id|$b" : id;

          final finalMap = widget.agentPhysicalQtys[-1];
          if (finalMap != null && finalMap[key] != null) {
            checkableCount++;
            if (_selectedKeys.contains(key)) selectedCount++;
          }
        }

        final finalMap = widget.agentPhysicalQtys[-1];
        _selectedKeys.removeWhere((k) => finalMap == null || finalMap[k] == null);

        _allCheckableSelected = checkableCount > 0 && selectedCount == checkableCount;
      }

      _isLoading = false;
    });
  }

  int? _getAgreedValue(String key) {
    if (_verificationAgents.isEmpty) return null;
    int? firstVal;
    for (int idx in _verificationAgents) {
      int? val = widget.agentPhysicalQtys[idx]?[key];
      if (val == null) return null; // Missing count from one agent
      if (firstVal == null) {
        firstVal = val;
      } else if (firstVal != val) {
        return null; // Mismatch between agents
      }
    }
    return firstVal;
  }

  dynamic _getAdminColValue(dynamic p, String key, List<dynamic> source) {
    if (p == null) return null;
    String id = p.id?.toString() ?? "";
    String b = p.batch?.toString() ?? "";
    String idKey = widget.batchMode ? "$id|$b" : id;

    if (key == 'checked') {
      if (id.isEmpty) return "NOT CHECKED";
      // Admin view status is "CHECKED" only if the Final Qty has been entered (agent index -1)
      bool hasFinalQty = widget.agentPhysicalQtys[-1]?[idKey] != null;
      return hasFinalQty ? "CHECKED" : "NOT CHECKED";
    }
    if (key == 'sl') {
      return source.indexOf(p) + 1;
    }
    if (key == 'name') return p.name ?? "-";
    if (key == 'series') return p.rack ?? "";
    if (key == 'packSize') {
      return p.packSize ?? 0;
    }
    if (key == 'stock') return p.stock ?? 0;
    if (key == 'expiry') return p.expiry ?? "-";
    if (key == 'final') {
      int stockVal = (p.stock as num?)?.toInt() ?? 0;
      int? f = widget.agentPhysicalQtys[-1]?[idKey];
      if (f == null) return null;
      return f - stockVal;
    }
    if (key == 'adjustment') {
      int stockVal = (p.stock as num?)?.toInt() ?? 0;
      int? finalQty = widget.agentPhysicalQtys[-1]?[idKey];
      if (finalQty == null) return null;
      return finalQty - stockVal;
    }
    if (key == 'lcostChange') {
      int stockVal = (p.stock as num?)?.toInt() ?? 0;
      int? finalPhys = widget.agentPhysicalQtys[-1]?[idKey];
      if (finalPhys == null) return 0.0;
      int pSize = (p.packSize as num?)?.toInt() ?? 1;
      if (pSize <= 0) pSize = 1;
      double lcost = (p.landingCost as num?)?.toDouble() ?? 0.0;
      return (finalPhys - stockVal) * (lcost / pSize);
    }
    if (key.startsWith('agentDiff_')) {
      int agentIdx = int.tryParse(key.split('_')[1]) ?? 0;
      return widget.agentPhysicalQtys[agentIdx]?[idKey];
    }
    return null;
  }

  String _getItemVerificationStatus(String key) {
    if (_verificationAgents.isEmpty) return "";

    bool allAttended = true;
    int? firstVal;
    bool mismatch = false;

    for (int agentIdx in _verificationAgents) {
      final agentMap = widget.agentPhysicalQtys[agentIdx];
      if (agentMap == null) {
        allAttended = false;
        break;
      }
      int? phys = agentMap[key];
      if (phys == null) {
        allAttended = false;
        break;
      }
      if (firstVal == null) {
        firstVal = phys;
      } else if (phys != firstVal) {
        mismatch = true;
        break;
      }
    }

    if (!allAttended || mismatch) return "NOT VERIFIED";
    return "VERIFIED";
  }

  void _moveFocus(int currentIndex, int direction) {
    int nextIndex = currentIndex + direction;
    if (nextIndex >= 0 && nextIndex < _filteredItems.length) {
      final nextItem = _filteredItems[nextIndex];
      String nextId = (nextItem.id ?? "").toString();
      String nextBatch = (nextItem.batch ?? "").toString();
      String nextKey = widget.batchMode ? "$nextId|$nextBatch" : nextId;
      _getFocusNode(nextKey).requestFocus();
    }
  }

  bool _isNearExpiry(String expiry) {
    if (!widget.enableExpiryFilter || widget.expiryLimit == null) return false;
    if (expiry.isEmpty) return false;
    try {
      final pts = expiry.split('/');
      int month = int.parse(pts[0]);
      int year = 2000 + int.parse(pts[1]);
      final date = DateTime(year, month, 1);
      return !date.isAfter(widget.expiryLimit!);
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context) {
    double totalTableWidth = _showCheckedListOnly ? 0 : 40; // Base width for checkbox column
    if (_showCheckedListOnly) {
      totalTableWidth += (widget.adminColWidths["sl"] ?? 40);
      totalTableWidth += (widget.adminColWidths["name"] ?? 280);
      totalTableWidth += (widget.adminColWidths["packSize"] ?? 60);
      totalTableWidth += (widget.adminColWidths["batch"] ?? 80);
      totalTableWidth += (widget.adminColWidths["adjustment"] ?? 90);
    } else {
      for (var w in widget.adminColWidths.values) {
        totalTableWidth += w;
      }
      totalTableWidth += (widget.agentNames.length * 65);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildAgentVerificationBar(),
          const SizedBox(height: 12),
          Expanded(
            child: Scrollbar(
              controller: _adminScrollCtrl,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller: _adminScrollCtrl,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: totalTableWidth,
                  child: Column(
                    children: [
                      _buildTableHeader(),
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _filteredItems.isEmpty
                                ? const Center(child: Text("No items have been counted yet.", style: TextStyle(color: Colors.grey)))
                                : ListView.builder(
                                    itemCount: _filteredItems.length,
                                    itemExtent: 64,
                                    itemBuilder: (context, index) {
                                      final p = _filteredItems[index];
                                      String id = (p.id ?? "").toString();
                                      String b = (p.batch ?? "").toString();
                                      String key = widget.batchMode ? "$id|$b" : id;
                                      return _AdminTableRow(
                                        key: ValueKey("admin_$key"),
                                        p: p,
                                        index: index,
                                        batchMode: widget.batchMode,
                                        agentNames: widget.agentNames,
                                        agentPhysicalQtys: widget.agentPhysicalQtys,
                                        colWidths: widget.adminColWidths,
                                        isSelected: _selectedKeys.contains(key),
                                        isNearExpiry: _isNearExpiry(p.expiry),
                                        verificationAgents: _verificationAgents,
                                        onSelected: (v) => setState(() => v! ? _selectedKeys.add(key) : _selectedKeys.remove(key)),
                                        onUpdatePhysical: (agentIdx, key, val) {
                                          widget.onUpdatePhysical(agentIdx, key, val);
                                          // Re-run filter/select-all logic after a small delay to keep UI snappy
                                          Future.microtask(() => _filterItems());
                                        },
                                        onReset: () => widget.onResetItem(key),
                                        focusNode: _getFocusNode(key),
                                        onFocus: () => _focusedIndex = index,
                                        onSubmitted: () => _moveFocus(index, 1),
                                        getItemVerificationStatus: _getItemVerificationStatus,
                                        showCheckedListOnly: _showCheckedListOnly,
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 24),
          Row(
            children: [
              _buildFinancialSummary(),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _selectedKeys.isEmpty ? null : _confirmAndSync,
                icon: const Icon(Icons.sync_rounded, color: Colors.white),
                label: const Text("ADJUST & MOVE TO CHECKED", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              ),
            ],
          )
        ],
      ),
    );
  }

  Future<void> _confirmAndSync() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Finalize & Adjust Stock"),
        content: Text("This will update the inventory and move the ${_selectedKeys.length} selected items to the checked list. Do you want to proceed?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
            child: const Text("FINALIZE & ADJUST", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      _performFinalSync();
    }
  }

  void _performFinalSync() async {
    setState(() => _isLoading = true);
    try {
      final pharma = Provider.of<PharmacyProvider>(context, listen: false);
      List<StockAdjustmentItem> adjustmentItems = [];

      for (String key in _selectedKeys) {
        final p = _filteredItems.firstWhere((item) {
          String itemId = (item.id ?? "").toString();
          String itemBatch = (item.batch ?? "").toString();
          String k = widget.batchMode ? "$itemId|$itemBatch" : itemId;
          return k == key;
        });

        int systemQty = (p.stock as num?)?.toInt() ?? 0;
        int? finalQty = widget.agentPhysicalQtys[-1]?[key];
        
        if (finalQty != null) {
          int diff = finalQty - systemQty;
          if (diff != 0) {
            int pSize = (p.packSize as num?)?.toInt() ?? 1;
            if (pSize <= 0) pSize = 1;

            double effectiveCost = (p.landingCost as num?)?.toDouble() ?? 0.0;
            if (effectiveCost <= 0) {
              effectiveCost = (p.purchaseRate as num?)?.toDouble() ?? 0.0;
            }
            double unitRate = effectiveCost / pSize;

            adjustmentItems.add(StockAdjustmentItem(
              product: p,
              qty: diff,
              purchaseRate: (p.purchaseRate as num?)?.toDouble() ?? 0.0,
              total: diff * unitRate,
            ));
          }
        }
      }

      if (adjustmentItems.isNotEmpty) {
        final adj = StockAdjustment(
          entryNo: "AUTO",
          date: DateTime.now(),
          doneBy: "ADMIN (STOCK CHECK)",
          reason: "ADJUSTED THROUGH STOCK CHECKING",
          items: adjustmentItems,
          grandTotal: adjustmentItems.fold(0.0, (sum, i) => sum + (i.total)),
        );

        await pharma.saveStockAdjustment(adj);
      }

      // Notify parent to sync keys and cleanup
      widget.onMoveToChecked(_selectedKeys);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Sync Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _filterItems();
      }
    }
  }

  Widget _buildFinancialSummary() {
    double totalMrpDiff = 0;
    double totalLCostDiff = 0;

    for (var p in _filteredItems) {
      if (p == null) continue;
      String id = (p.id ?? "").toString();
      String b = (p.batch ?? "").toString();
      String key = widget.batchMode ? "$id|$b" : id;
      if (!_selectedKeys.contains(key)) continue;

      final finalMap = widget.agentPhysicalQtys[-1];
      int? finalPhys = finalMap != null ? finalMap[key] : null;
      if (finalPhys == null) continue;
      int systemQty = (p.stock as num?)?.toInt() ?? 0;
      int diff = finalPhys - systemQty;

      int pSize = (p.packSize as num?)?.toInt() ?? 1;
      if (pSize <= 0) pSize = 1;

      double mrp = (p.mrp as num?)?.toDouble() ?? 0.0;
      double lcost = (p.landingCost as num?)?.toDouble() ?? 0.0;

      totalMrpDiff += diff * (mrp.abs() / pSize);
      totalLCostDiff += diff * (lcost.abs() / pSize);
    }

    return Row(
      children: [
        _summaryFinancialBadge("MRP CHANGE", totalMrpDiff),
        const SizedBox(width: 12),
        _summaryFinancialBadge("L.COST CHANGE", totalLCostDiff),
      ],
    );
  }

  Widget _summaryFinancialBadge(String label, double value) {
    final bool isNegative = value < 0;
    final color = isNegative ? Colors.red : (value > 0 ? Colors.green : Colors.grey);
    final sign = value > 0 ? "+" : (isNegative ? "-" : "");
    final absVal = value.abs().toStringAsFixed(2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
          Text("$sign$absVal",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget _buildAgentVerificationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_rounded, size: 20, color: Color(0xFF3F51B5)),
          const SizedBox(width: 12),
          const Text("VERIFY AGENTS:",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF3F51B5), letterSpacing: 0.5)),
          const SizedBox(width: 16),
          ...widget.agentNames.asMap().entries.map((entry) {
            int idx = entry.key;
            String name = entry.value;
            bool isSelected = _verificationAgents.contains(idx);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (!isSelected) {
                    _verificationAgents.add(idx);
                  } else if (_verificationAgents.length > 1) {
                    _verificationAgents.remove(idx);
                  }
                  _filterItems();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF3F51B5) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isSelected ? const Color(0xFF3F51B5) : Colors.grey.shade300, width: 1.5),
                  boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF3F51B5).withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))] : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSelected) ...[
                      const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                    ],
                    Text(name ?? "Agent",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.grey.shade700
                      )),
                  ],
                ),
              ),
            );
          }),
          const Spacer(),
          _buildCheckedListToggle(),
        ],
      ),
    );
  }

  Widget _buildCheckedListToggle() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showCheckedListOnly = !_showCheckedListOnly;
          _filterItems();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _showCheckedListOnly ? Colors.indigo : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _showCheckedListOnly ? Colors.indigo : Colors.grey.shade300, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_showCheckedListOnly ? Icons.arrow_back_rounded : Icons.checklist_rounded, 
              color: _showCheckedListOnly ? Colors.white : Colors.grey.shade700, size: 18),
            const SizedBox(width: 8),
            Text(_showCheckedListOnly ? "BACK TO ADJUSTMENT" : "CHECKED LIST",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _showCheckedListOnly ? Colors.white : const Color(0xFF616161)
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      color: Colors.grey.shade50,
      height: 52,
      child: Row(
        children: [
          if (!_showCheckedListOnly)
            Container(
                width: 40,
                decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300))),
                child: Checkbox(
                  value: _allCheckableSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v!) {
                        for (var p in _filteredItems) {
                          String itemId = (p.id ?? "").toString();
                          String itemBatch = (p.batch ?? "").toString();
                          String key = widget.batchMode ? "$itemId|$itemBatch" : itemId;
                          if (widget.agentPhysicalQtys[-1]?[key] != null) {
                            _selectedKeys.add(key);
                          }
                        }
                      } else {
                        _selectedKeys.clear();
                      }
                    });
                    _filterItems(); // Update _allCheckableSelected
                  },
                  visualDensity: VisualDensity.compact,
                )),

          if (!_showCheckedListOnly)
            _GridHeaderCell(
              key: const ValueKey("admin_header_checked"),
              col: _ColInfo("checked", "CHECKED", align: TextAlign.center),
              width: widget.adminColWidths["checked"] ?? 70,
              currentFilter: _adminFilters["checked"],
                            onQuickFilter: (cond, val) => _updateAdminFilter("checked", cond, val, ColumnType.text),
            ),

          _GridHeaderCell(
            key: const ValueKey("admin_header_sl"),
            col: _ColInfo("sl", "SL", type: ColumnType.numeric, align: TextAlign.center),
            width: widget.adminColWidths["sl"] ?? 40,
            currentFilter: _adminFilters["sl"],
                        onQuickFilter: (cond, val) => _updateAdminFilter("sl", cond, val, ColumnType.numeric),
          ),

          _GridHeaderCell(
            key: const ValueKey("admin_header_name"),
            col: _ColInfo("name", "PRODUCT", flex: 3.0, align: TextAlign.left),
            width: widget.adminColWidths["name"] ?? 280,
            currentFilter: _adminFilters["name"],
                        onQuickFilter: (cond, val) => _updateAdminFilter("name", cond, val, ColumnType.text),
            onResize: (w) => widget.onResizeColumn("name", w),
          ),
          _GridHeaderCell(
            key: const ValueKey("admin_header_packSize"),
            col: _ColInfo("packSize", "PACK", flex: 1.0, type: ColumnType.numeric, align: TextAlign.center),
            width: widget.adminColWidths["packSize"] ?? 60,
            currentFilter: _adminFilters["packSize"],
                        onQuickFilter: (cond, val) => _updateAdminFilter("packSize", cond, val, ColumnType.numeric),
            onResize: (w) => widget.onResizeColumn("packSize", w),
          ),
          _GridHeaderCell(
            key: const ValueKey("admin_header_batch"),
            col: _ColInfo("batch", "BATCH", align: TextAlign.left),
            width: widget.adminColWidths["batch"] ?? 80,
            currentFilter: _adminFilters["batch"],
                        onQuickFilter: (cond, val) => _updateAdminFilter("batch", cond, val, ColumnType.text),
            onResize: (w) => widget.onResizeColumn("batch", w),
          ),
          if (!_showCheckedListOnly) ...[
            _GridHeaderCell(
              key: const ValueKey("admin_header_series"),
              col: _ColInfo("series", "RACK", align: TextAlign.left),
              width: widget.adminColWidths["series"] ?? 90,
              currentFilter: _adminFilters["series"],
                            onQuickFilter: (cond, val) => _updateAdminFilter("series", cond, val, ColumnType.text),
              onResize: (w) => widget.onResizeColumn("series", w),
            ),
            _GridHeaderCell(
              key: const ValueKey("admin_header_stock"),
              col: _ColInfo("stock", "STOCK", flex: 1.0, type: ColumnType.numeric, align: TextAlign.center),
              width: widget.adminColWidths["stock"] ?? 80,
              currentFilter: _adminFilters["stock"],
                            onQuickFilter: (cond, val) => _updateAdminFilter("stock", cond, val, ColumnType.numeric),
              onResize: (w) => widget.onResizeColumn("stock", w),
            ),

            ...widget.agentNames.asMap().entries.where((e) => _verificationAgents.contains(e.key)).map((entry) {
              int idx = entry.key;
              String name = entry.value;
              String colKey = "agentDiff_$idx";
              return _GridHeaderCell(
                key: ValueKey("admin_header_$colKey"),
                col: _ColInfo(colKey, name.toUpperCase(), type: ColumnType.numeric, align: TextAlign.center),
                width: 65,
                currentFilter: _adminFilters[colKey],
                                onQuickFilter: (cond, val) => _updateAdminFilter(colKey, cond, val, ColumnType.numeric),
              );
            }),
          ],

          _GridHeaderCell(
            key: const ValueKey("admin_header_adjustment"),
            col: _ColInfo("adjustment", _showCheckedListOnly ? "CHANGE" : "ADJUSTMENT", flex: 1.0, type: ColumnType.numeric, align: TextAlign.center),
            width: widget.adminColWidths["adjustment"] ?? 90,
            currentFilter: _adminFilters["adjustment"],
                        onQuickFilter: (cond, val) => _updateAdminFilter("adjustment", cond, val, ColumnType.numeric),
            onResize: (w) => widget.onResizeColumn("adjustment", w),
          ),
          if (!_showCheckedListOnly) ...[
            _GridHeaderCell(
              key: const ValueKey("admin_header_final"),
              col: _ColInfo("final", "FINAL QTY", flex: 1.0, type: ColumnType.numeric, align: TextAlign.center),
              width: widget.adminColWidths["final"] ?? 90,
              currentFilter: _adminFilters["final"],
                            onQuickFilter: (cond, val) => _updateAdminFilter("final", cond, val, ColumnType.numeric),
              onResize: (w) => widget.onResizeColumn("final", w),
            ),
            _GridHeaderCell(
              key: const ValueKey("admin_header_expiry"),
              col: _ColInfo("expiry", "EXPIRY", flex: 1.0, align: TextAlign.center),
              width: widget.adminColWidths["expiry"] ?? 100,
              currentFilter: _adminFilters["expiry"],
                            onQuickFilter: (cond, val) => _updateAdminFilter("expiry", cond, val, ColumnType.text),
              onResize: (w) => widget.onResizeColumn("expiry", w),
            ),
            _GridHeaderCell(
              key: const ValueKey("admin_header_lcostChange"),
              col: _ColInfo("lcostChange", "L.COST CHANGE", flex: 1.0, type: ColumnType.numeric, align: TextAlign.center),
              width: widget.adminColWidths["lcostChange"] ?? 110,
              currentFilter: _adminFilters["lcostChange"],
                            onQuickFilter: (cond, val) => _updateAdminFilter("lcostChange", cond, val, ColumnType.numeric),
              onResize: (w) => widget.onResizeColumn("lcostChange", w),
            ),
          ],
        ],
      ),
    );
  }

  void _updateAdminFilter(String key, String condition, String value, ColumnType type) {
    setState(() {
      if (condition == 'Clear') {
        _adminFilters.remove(key);
      } else {
        _adminFilters[key] = {
          'mode': 'rules',
          'type': type,
          'condition': condition,
          'value1': value,
          'value2': '',
        };
      }
    });
    _filterItems();
  }

}

class _AdminTableRow extends StatefulWidget {
  final dynamic p;
  final int index;
  final bool batchMode;
  final List<String> agentNames;
  final Map<int, Map<String, int?>> agentPhysicalQtys;
  final Map<String, double> colWidths;
  final bool isSelected;
  final bool isNearExpiry;
  final Set<int> verificationAgents;
  final Function(bool?) onSelected;
  final Function(int, String, int?) onUpdatePhysical;
  final VoidCallback onReset;
  final FocusNode focusNode;
  final VoidCallback onFocus;
  final VoidCallback onSubmitted;
  final String Function(String) getItemVerificationStatus;
  final bool showCheckedListOnly;

  const _AdminTableRow({
    super.key,
    required this.p,
    required this.index,
    required this.batchMode,
    required this.agentNames,
    required this.agentPhysicalQtys,
    required this.colWidths,
    required this.isSelected,
    required this.isNearExpiry,
    required this.verificationAgents,
    required this.onSelected,
    required this.onUpdatePhysical,
    required this.onReset,
    required this.focusNode,
    required this.onFocus,
    required this.onSubmitted,
    required this.getItemVerificationStatus,
    this.showCheckedListOnly = false,
  });

  @override
  State<_AdminTableRow> createState() => _AdminTableRowState();
}

class _AdminTableRowState extends State<_AdminTableRow> {
  late TextEditingController _finalController;
  int? _lastAgreedVal;

  @override
  void initState() {
    super.initState();
    String id = widget.p.id?.toString() ?? "";
    String b = widget.p.batch?.toString() ?? "";
    String key = widget.batchMode ? "$id|$b" : id;

    _lastAgreedVal = _getAgreedValue(key);
    int? initialFinal = widget.agentPhysicalQtys[-1]?[key] ?? _lastAgreedVal;

    _finalController = TextEditingController(text: initialFinal?.toString() ?? "");

    if (initialFinal != null && widget.agentPhysicalQtys[-1]?[key] == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onUpdatePhysical(-1, key, initialFinal);
      });
    }

    widget.focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (widget.focusNode.hasFocus) widget.onFocus();
  }

  void _checkAndApplyAutoFill() {
    String id = widget.p.id?.toString() ?? "";
    String b = widget.p.batch?.toString() ?? "";
    String key = widget.batchMode ? "$id|$b" : id;
    int? agreed = _getAgreedValue(key);
    int? currentFinal = widget.agentPhysicalQtys[-1]?[key];

    if (agreed != null && agreed != _lastAgreedVal) {
      // If agents now agree on a count, auto-fill the Final box if it's currently blank or matches the old agreement
      if (currentFinal == null || currentFinal == _lastAgreedVal) {
        _finalController.text = agreed.toString();
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onUpdatePhysical(-1, key, agreed);
        });
      }
    } else if (agreed == null && _lastAgreedVal != null) {
      // If agents no longer agree, clear Final box only if it was auto-filled from the previous agreement
      if (currentFinal == _lastAgreedVal) {
        _finalController.clear();
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onUpdatePhysical(-1, key, null);
        });
      }
    }
    _lastAgreedVal = agreed;
  }

  int? _getAgreedValue(String key) {
    if (widget.verificationAgents.isEmpty) return null;

    int? firstVal;

    for (int idx in widget.verificationAgents) {
      final agentMap = widget.agentPhysicalQtys[idx];
      if (agentMap == null || !agentMap.containsKey(key) || agentMap[key] == null) {
        return null;
      }

      int currentVal = agentMap[key]!;
      if (firstVal == null) {
        firstVal = currentVal;
      } else if (firstVal != currentVal) {
        return null;
      }
    }

    return firstVal;
  }

  @override
  void didUpdateWidget(_AdminTableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Sync controller if final count changed externally
    String id = widget.p.id?.toString() ?? "";
    String b = widget.p.batch?.toString() ?? "";
    String key = widget.batchMode ? "$id|$b" : id;
    
    int? finalVal = widget.agentPhysicalQtys[-1]?[key];
    String expectedText = finalVal?.toString() ?? "";
    
    if (_finalController.text != expectedText && !widget.focusNode.hasFocus) {
       _finalController.text = expectedText;
    }

    _checkAndApplyAutoFill();
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    _finalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String id = widget.p.id?.toString() ?? "";
    String b = widget.p.batch?.toString() ?? "";
    String key = widget.batchMode ? "$id|$b" : id;

    final agentQtys = widget.agentPhysicalQtys;
    int? finalVal = agentQtys[-1]?[key];
    int stockVal = 0;
    if (widget.p != null) {
      stockVal = (widget.p.stock as num?)?.toInt() ?? 0;
    }

    int pSize = 1;
    if (widget.p != null) {
      pSize = (widget.p.packSize as num?)?.toInt() ?? 1;
    }
    if (pSize <= 0) pSize = 1;

    double lcostChange = 0;
    if (finalVal != null) {
      int diff = finalVal - stockVal;
      double lcost = 0.0;
      if (widget.p != null) {
        lcost = (widget.p.landingCost as num?)?.toDouble() ?? 0.0;
      }
      lcostChange = (lcost.abs() / pSize) * diff;
    }

    String adjustmentText = "-";
    Color adjustmentColor = Colors.blueGrey;
    if (finalVal != null) {
      int diff = finalVal - stockVal;
      adjustmentText = diff == 0 ? "0" : "${diff > 0 ? '+' : ''}$diff";
      adjustmentColor = diff == 0 ? Colors.blue : (diff > 0 ? Colors.green : Colors.red);
    }

    int? agreedCount = _getAgreedValue(key);
    bool isAgreedFill = finalVal != null && agreedCount != null && finalVal == agreedCount;

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: widget.isSelected ? Colors.indigo.withValues(alpha: 0.05) : Colors.transparent,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!widget.showCheckedListOnly)
            Container(
                width: 40,
                decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
                child: Checkbox(
                  value: widget.isSelected,
                  onChanged: finalVal == null ? null : widget.onSelected,
                  visualDensity: VisualDensity.compact,
                  activeColor: Colors.indigo,
                )),
          if (!widget.showCheckedListOnly)
            Container(
              width: widget.colWidths["checked"] ?? 70,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
              child: _buildAttendanceMark(finalVal != null),
            ),
          Container(
              width: widget.colWidths["sl"] ?? 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
              child: Text("${widget.index + 1}", style: const TextStyle(fontSize: 10, color: Colors.grey))),
          Container(
              width: widget.colWidths["name"] ?? 280,
              padding: const EdgeInsets.only(left: 12, right: 8),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
              child: Text(widget.p.name ?? "-", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          Container(
              width: widget.colWidths["packSize"] ?? 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
              child: Text("${widget.p.packSize ?? 0}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),

          Container(
              width: widget.colWidths["batch"] ?? 80,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
              child: Text(widget.batchMode ? (widget.p.batch ?? "-") : "-", style: const TextStyle(fontSize: 11, color: Colors.blueGrey))),
          if (!widget.showCheckedListOnly) ...[
            Container(
                width: widget.colWidths["series"] ?? 90,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
                child: Text("${widget.p.rack ?? ""}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
            Container(
                width: widget.colWidths["stock"] ?? 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
                child: Text("${widget.p.stock ?? 0}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
            ...widget.agentNames.asMap().entries.where((e) => widget.verificationAgents.contains(e.key)).map((entry) {
              int agentIdx = entry.key;
              final agentMap = widget.agentPhysicalQtys[agentIdx];
              int? phys = agentMap != null ? agentMap[key] : null;
              
              if (phys == null) return Container(width: 65, decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))), child: const Center(child: Text("-", style: TextStyle(color: Colors.grey))));
              return Container(
                  width: 65,
                  decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
                  child: Center(
                    child: Text("$phys",
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black87,
                            fontWeight: FontWeight.normal)),
                  ));
            }),
          ],
          Container(
              width: widget.colWidths["adjustment"] ?? 90,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
              child: Text(adjustmentText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: adjustmentColor))),
          if (!widget.showCheckedListOnly) ...[
          Container(
              width: widget.colWidths["final"] ?? 75,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
              child: SizedBox(
                height: 52,
                child: TextField(
                  controller: _finalController,
                  focusNode: widget.focusNode,
                  textAlign: TextAlign.center,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                    fillColor: isAgreedFill ? const Color(0xFFE8F5E9) : Colors.white,
                    filled: true,
                  ),
                  onChanged: (v) {
                    String id = widget.p.id?.toString() ?? "";
                    String b = widget.p.batch?.toString() ?? "";
                    String key = widget.batchMode ? "$id|$b" : id;
                    if (v.trim().isEmpty) {
                      widget.onUpdatePhysical(-1, key, null);
                      setState(() {});
                      return;
                    }
                    int? newVal = int.tryParse(v);
                    if (newVal != null) {
                      widget.onUpdatePhysical(-1, key, newVal);
                      setState(() {});
                    }
                  },
                    onSubmitted: (v) => widget.onSubmitted(),
                  ),
                )),
            Container(
                width: widget.colWidths["expiry"] ?? 100,
                alignment: Alignment.center,
                decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
                child: Text(widget.p.expiry ?? "-",
                    style: TextStyle(
                        fontSize: 10,
                        color: widget.isNearExpiry ? Colors.red : Colors.blueGrey,
                        fontWeight: widget.isNearExpiry ? FontWeight.bold : FontWeight.normal))),
            Container(
                width: widget.colWidths["lcostChange"] ?? 110,
                alignment: Alignment.center,
                decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
                child: Text(
                  "${lcostChange > 0 ? '+' : ''}${lcostChange.toStringAsFixed(2)}",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: lcostChange == 0 ? Colors.blueGrey : (lcostChange > 0 ? Colors.green : Colors.red)
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildAttendanceMark(bool attended) {
    if (!attended) {
      return const Text("NOT CHECKED",
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.red));
    }
    return const Text("CHECKED",
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF4CAF50)));
  }

  Widget _buildDiffIndicatorStatic(int diff) {
    if (diff == 0) return const Text("TALLY", style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold));
    return Text("${diff > 0 ? '+' : ''}$diff",
        style: TextStyle(fontSize: 11, color: diff > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold));
  }
}

enum ColumnType { text, numeric, date }

class _ColInfo {
  final String key;
  final String label;
  final double flex;
  final TextAlign align;
  final ColumnType type;
  _ColInfo(this.key, this.label, {this.flex = 1, this.align = TextAlign.left, this.type = ColumnType.text});
}

class _GridHeaderCell extends StatefulWidget {
  final _ColInfo col;
  final double width;
  final Function(String condition, String value) onQuickFilter;
  final Map<String, dynamic>? currentFilter;
  final Function(double)? onResize;

  const _GridHeaderCell({
    super.key,
    required this.col,
    required this.width,
    required this.onQuickFilter,
    this.currentFilter,
    this.onResize,
  });

  @override
  State<_GridHeaderCell> createState() => _GridHeaderCellState();
}

class _GridHeaderCellState extends State<_GridHeaderCell> {
  late String _quickCondition;
  final TextEditingController _quickCtrl = TextEditingController();
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _syncFromProps();
  }

  @override
  void didUpdateWidget(_GridHeaderCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentFilter != oldWidget.currentFilter) {
      _syncFromProps();
    }
  }

  void _syncFromProps() {
    if (widget.currentFilter == null) {
      if (_quickCtrl.text.isNotEmpty) _quickCtrl.clear();
      _quickCondition = widget.col.type == ColumnType.text ? 'Contains' : 'Equals';
    } else {
      _quickCondition = widget.currentFilter!['condition'];
      final newValue = widget.currentFilter!['value1'] ?? "";
      if (_quickCtrl.text != newValue) {
        _quickCtrl.text = newValue;
      }
    }
  }

  @override
  void dispose() {
    _quickCtrl.dispose();
    super.dispose();
  }

  String _getConditionSymbol() {
    switch (_quickCondition) {
      case 'Equals': return '=';
      case 'Does Not Equal': return '!=';
      case 'Contains': return 'inc';
      case 'Does Not Contain': return '!inc';
      case 'Begins With': return 'A..';
      case 'Ends With': return '..Z';
      case 'Greater Than': return '>';
      case 'Less Than': return '<';
      default: return '=';
    }
  }

  void _showConditionMenu(TapDownDetails details) async {
    List<String> items = widget.col.type == ColumnType.text
        ? ['Equals', 'Does Not Equal', 'Contains', 'Does Not Contain', 'Begins With', 'Ends With']
        : ['Equals', 'Does Not Equal', 'Greater Than', 'Less Than'];

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy + 10, details.globalPosition.dx, 0),
      items: items.map((e) => PopupMenuItem(value: e, height: 30, child: Text(e, style: const TextStyle(fontSize: 11)))).toList(),
    );

    if (result != null) {
      setState(() => _quickCondition = result);
      if (_quickCtrl.text.isNotEmpty) widget.onQuickFilter(_quickCondition, _quickCtrl.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300))),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6, top: 4),
                        child: Text(widget.col.label,
                            textAlign: widget.col.align,
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    // Filter icon removed
                  ],
                ),
                Container(
                  height: 20,
                  margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300)),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTapDown: _showConditionMenu,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          color: Colors.grey.shade50,
                          alignment: Alignment.center,
                          child: Text(_getConditionSymbol(), style: const TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _quickCtrl,
                          textAlign: widget.col.align,
                          style: const TextStyle(fontSize: 10),
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4), border: InputBorder.none),
                          onChanged: (val) {
                            if (val.isEmpty) {
                              widget.onQuickFilter('Clear', '');
                            } else {
                              widget.onQuickFilter(_quickCondition, val);
                            }
                            setState(() {}); // Update visibility
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.onResize != null)
              Positioned(
                right: -4,
                top: 0,
                bottom: 0,
                width: 8,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) {
                      widget.onResize!(widget.width + details.delta.dx);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

