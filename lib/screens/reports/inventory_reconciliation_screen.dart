import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../database/db_helper.dart';

class _ReconRow {
  final String productId, batch, expiry, status, note;
  final List<Map<String, Object?>> legacy, ledger;
  final int legacyQty, ledgerQty;
  final bool unresolved;
  int get difference => legacyQty - ledgerQty;
  _ReconRow({required this.productId, required this.batch, required this.expiry, required this.status, required this.note, required this.legacy, required this.ledger, required this.legacyQty, required this.ledgerQty, this.unresolved = false});
}

class InventoryReconciliationScreen extends StatefulWidget {
  const InventoryReconciliationScreen({super.key});
  @override
  State<InventoryReconciliationScreen> createState() => _InventoryReconciliationScreenState();
}

class _InventoryReconciliationScreenState extends State<InventoryReconciliationScreen> {
  bool _loading = true;
  String? _error, _schemaWarning;
  List<_ReconRow> _rows = [];
  String _norm(Object? v) => (v?.toString() ?? '').trim().toLowerCase();
  String _key(Object? p, Object? b, Object? e) => '${_norm(p)}|\u0000${_norm(b)}|\u0000${_norm(e)}';
  int _int(Object? v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<Set<String>> _tableColumns(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((r) => r['name']?.toString().toLowerCase() ?? '').where((s) => s.isNotEmpty).toSet();
  }

  Future<List<Map<String, Object?>>> _selectIfPresent(Database db, String table, Set<String> columns) async {
    if (columns.isEmpty) return [];
    return db.rawQuery('SELECT * FROM $table');
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _schemaWarning = null; });
    try {
      final db = await DbHelper.instance.database;
      // Only PRAGMA metadata reads and SELECTs are issued by this report.
      final ledgerCols = await _tableColumns(db, 'stock_ledger');
      if (ledgerCols.isEmpty) throw StateError('stock_ledger table is unavailable; ledger source rows cannot be read.');
      final legacyCols = await _tableColumns(db, 'stock_batches');
      final masterCols = await _tableColumns(db, 'batch_master');
      final warnings = <String>[];
      const legacyRequired = {'product_id', 'batch_number', 'expiry_date', 'current_stock'};
      const masterRequired = {'batch_id', 'product_id', 'batch_number', 'expiry_date'};
      if (!legacyCols.containsAll(legacyRequired)) warnings.add('stock_batches missing table/required columns; legacy comparison is unavailable.');
      if (!masterCols.containsAll(masterRequired)) warnings.add('batch_master missing table/required columns; ledger batch identity cannot be resolved.');
      final hasIn = ledgerCols.contains('qty_in'), hasOut = ledgerCols.contains('qty_out'), hasDelta = ledgerCols.contains('quantity_delta');
      if ((!hasIn || !hasOut) && !hasDelta) warnings.add('No recognized ledger quantity columns; all ledger rows are unresolved.');
      if ((hasIn && !hasOut) || (!hasIn && hasOut)) warnings.add('Only one of qty_in/qty_out exists; affected rows are unresolved.');
      if (!ledgerCols.contains('batch_id') || !ledgerCols.contains('product_id')) warnings.add('Ledger identity columns are missing; rows are retained as unresolved.');
      final canReadLegacy = legacyCols.containsAll(legacyRequired);
      final canResolveMaster = masterCols.containsAll(masterRequired);
      final legacy = canReadLegacy ? await _selectIfPresent(db, 'stock_batches', legacyCols) : <Map<String, Object?>>[];
      final masters = canResolveMaster ? await _selectIfPresent(db, 'batch_master', masterCols) : <Map<String, Object?>>[];
      final ledger = await _selectIfPresent(db, 'stock_ledger', ledgerCols);

      final masterById = {for (final m in masters) _norm(m['batch_id']): m};
      final Map<String, List<Map<String, Object?>>> legacyByKey = {}, ledgerByKey = {};
      final unresolved = <Map<String, Object?>>[];
      for (final r in legacy) {
        legacyByKey.putIfAbsent(_key(r['product_id'], r['batch_number'], r['expiry_date']), () => []).add(r);
      }
      for (final source in ledger) {
        final row = Map<String, Object?>.from(source);
        final identityAvailable = ledgerCols.contains('batch_id') && ledgerCols.contains('product_id');
        final master = identityAvailable && canResolveMaster ? masterById[_norm(row['batch_id'])] : null;
        final hasInOut = hasIn && hasOut;
        final inQty = hasIn ? _int(row['qty_in']) : 0;
        final outQty = hasOut ? _int(row['qty_out']) : 0;
        final delta = hasDelta ? _int(row['quantity_delta']) : 0;
        if (!identityAvailable) {
          unresolved.add({...row, '_reason': 'Ledger product/batch identity columns are absent.'});
          continue;
        }
        if (master != null) {
          if (!hasInOut) {
            unresolved.add({...row, '_reason': 'Resolved batch, but a complete qty_in/qty_out pair is unavailable; no net inferred.'});
            continue;
          }
          // Prefer the established pair once; quantity_delta may mirror it.
          row['_report_qty'] = inQty - outQty;
          row['_convention'] = 'batch_master ID, qty_in/qty_out (quantity_delta ignored to prevent double count)';
          ledgerByKey.putIfAbsent(_key(master['product_id'], master['batch_number'], master['expiry_date']), () => []).add(row);
          continue;
        }
        // Any nonzero delta without a master link is unresolved regardless of
        // legacy matches; raw delta and in/out values remain visible in details.
        if (delta != 0) {
          unresolved.add({...row, '_reason': 'Nonzero quantity_delta without batch_master match; alternate identity/unit cannot be safely compared.'});
          continue;
        }
        if (!hasInOut) {
          unresolved.add({...row, '_reason': 'Incomplete qty_in/qty_out pair; available value is not a complete net movement.'});
          continue;
        }
        if (inQty != 0 || outQty != 0) {
          final batchValue = ledgerCols.contains('batch_number') && _norm(row['batch_number']).isNotEmpty ? row['batch_number'] : row['batch_id'];
          row['_report_qty'] = inQty - outQty;
          row['_convention'] = 'orphan qty_in/qty_out; no batch_master match';
          row['_report_expiry'] = '(unknown: no batch_master row)';
          ledgerByKey.putIfAbsent(_key(row['product_id'], batchValue, row['_report_expiry']), () => []).add(row);
        } else {
          unresolved.add({...row, '_reason': 'No nonzero recognized movement; convention is unresolved.'});
        }
      }
      final keys = {...legacyByKey.keys, ...ledgerByKey.keys}.toList()..sort();
      final out = <_ReconRow>[];
      for (final key in keys) {
        final ls = legacyByKey[key] ?? [], gs = ledgerByKey[key] ?? [];
        final attrs = <String>{for (final r in [...ls, ...gs]) '${_norm(r['supplier_name'])}|${r['purchase_rate']}|${r['mrp']}|${r['packing']}'};
        final first = ls.isNotEmpty ? ls.first : gs.first;
        final status = ls.isEmpty ? 'Unmatched ledger' : gs.isEmpty ? 'Unmatched legacy' : (ls.length > 1 || gs.length > 1) ? 'Duplicate key' : 'Matched';
        final notes = <String>[];
        if (attrs.length > 1) notes.add('Attributes differ; key may combine lots (not proof).');
        if (gs.any((r) => (r['_convention'] ?? '').toString().startsWith('orphan'))) notes.add('Orphan ledger row; expiry unknown.');
        out.add(_ReconRow(productId: first['product_id']?.toString() ?? '', batch: first['batch_number']?.toString() ?? first['batch_id']?.toString() ?? '', expiry: first['expiry_date']?.toString() ?? first['_report_expiry']?.toString() ?? '', status: status, note: notes.join(' '), legacy: ls, ledger: gs, legacyQty: ls.fold<int>(0, (s,r) => s + _int(r['current_stock'])), ledgerQty: gs.fold<int>(0, (s,r) => s + _int(r['_report_qty']))));
      }
      for (final r in unresolved) {
        out.add(_ReconRow(productId: r['product_id']?.toString() ?? '', batch: r['batch_number']?.toString() ?? r['batch_id']?.toString() ?? '', expiry: '(unresolved)', status: 'Unresolved ledger convention', note: r['_reason']?.toString() ?? 'Unresolved source row.', legacy: const [], ledger: [r], legacyQty: 0, ledgerQty: 0, unresolved: true));
      }
      if (mounted) setState(() { _rows = out; _schemaWarning = warnings.isEmpty ? null : warnings.join(' '); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not read ledger source rows: $e'; _loading = false; });
    }
  }

  String _details(_ReconRow row) {
    final legacy = row.legacy.map((r) => 'Legacy row: qty=${r['current_stock']}, expiry=${r['expiry_date']}, supplier=${r['supplier_name']}, purchase=${r['purchase_rate']}, landing=${r['landing_cost']}, MRP=${r['mrp']}, sale=${r['sale_rate']}, pack=${r['packing']}').join('\n');
    final ledger = row.ledger.map((r) => 'Ledger row: source=${r['ledger_id'] ?? r['id']}, batch_id=${r['batch_id']}, batch_number=${r['batch_number']}, product=${r['product_id']}, expiry=${r['expiry_date'] ?? row.expiry}, qty_in=${r['qty_in']}, qty_out=${r['qty_out']}, quantity_delta=${r['quantity_delta']}, compared_qty=${r['_report_qty'] ?? 'not included'}, convention=${r['_convention'] ?? 'unresolved'}, voucher=${r['voucher_type'] ?? r['operation_type']}/${r['voucher_no'] ?? r['reference_no']}, timestamp=${r['timestamp'] ?? r['created_at']}, branch=${r['branch_id']}, terminal=${r['terminal_id']}, reason=${r['_reason'] ?? ''}').join('\n');
    return [legacy, ledger].where((s) => s.isNotEmpty).join('\n');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inventory Reconciliation (Read Only)'), actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh))]),
    body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!))) : Column(children: [
      const Material(color: Color(0xFFFFF3CD), child: Padding(padding: EdgeInsets.all(12), child: Text('Comparison only. No stock is changed. Key: product + normalized batch + expiry. Quantities are compared as stored; unit equivalence is not verified. Unresolved ledger rows retain raw source fields.'))),
      if (_schemaWarning != null) Material(color: Colors.orange.shade100, child: Padding(padding: const EdgeInsets.all(12), child: Text('Schema warning: $_schemaWarning'))),
      Padding(padding: const EdgeInsets.all(8), child: Wrap(spacing: 12, children: ['Matched', 'Unmatched legacy', 'Unmatched ledger', 'Duplicate key', 'Unresolved ledger convention'].map((s) => Chip(label: Text('$s: ${_rows.where((r) => r.status == s).length}'))).toList())),
      Expanded(child: ListView.builder(itemCount: _rows.length, itemBuilder: (context,i) {
        final r = _rows[i];
        final totals = r.unresolved ? 'Legacy not compared | Ledger raw movement unresolved' : 'Legacy ${r.legacyQty} | Ledger ${r.ledgerQty} | Difference ${r.difference}';
        return ExpansionTile(title: Text('${r.status} • ${r.productId} • ${r.batch} • ${r.expiry}'), subtitle: Text('$totals${r.note.isEmpty ? '' : '\n${r.note}'}'), children: [Padding(padding: const EdgeInsets.all(16), child: Align(alignment: Alignment.centerLeft, child: SelectableText(_details(r))))]);
      })),
    ]),
  );
}
