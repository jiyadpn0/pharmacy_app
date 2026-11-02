import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart' as sql;
import '../database/db_helper.dart';
import '../utils/app_formatters.dart';
import 'server_config_service.dart';
import 'supabase_realtime_service.dart';

class DiscrepancyField {
  final String fieldName;
  final String fieldLabel;
  final dynamic localValue;
  final dynamic serverValue;

  DiscrepancyField({
    required this.fieldName,
    required this.fieldLabel,
    this.localValue,
    this.serverValue,
  });

  bool get isMismatch {
    if (localValue == null && serverValue == null) return false;
    if (localValue == null || serverValue == null) return true;

    if (localValue is num && serverValue is num) {
      return (localValue.toDouble() - serverValue.toDouble()).abs() > 0.01;
    }
    final num? locNum = num.tryParse(localValue.toString());
    final num? srvNum = num.tryParse(serverValue.toString());
    if (locNum != null && srvNum != null) {
      return (locNum - srvNum).abs() > 0.01;
    }
    return localValue.toString().trim().toUpperCase() != serverValue.toString().trim().toUpperCase();
  }
}

class DiscrepancyItemRow {
  final String productName;
  final String batchNumber;
  final String expiryDate;
  final num qtyLoc;
  final num qtySrv;
  final num fQtyLoc;
  final num fQtySrv;
  final num mrpLoc;
  final num mrpSrv;
  final num rateLoc;
  final num rateSrv;
  final num discPercentLoc;
  final num discPercentSrv;
  final num taxPercentLoc;
  final num taxPercentSrv;
  final num totalLoc;
  final num totalSrv;
  final bool isMissingOnServer;
  final bool isMissingLocally;

  DiscrepancyItemRow({
    required this.productName,
    required this.batchNumber,
    required this.expiryDate,
    required this.qtyLoc,
    required this.qtySrv,
    this.fQtyLoc = 0,
    this.fQtySrv = 0,
    required this.mrpLoc,
    required this.mrpSrv,
    required this.rateLoc,
    required this.rateSrv,
    required this.discPercentLoc,
    required this.discPercentSrv,
    required this.taxPercentLoc,
    required this.taxPercentSrv,
    required this.totalLoc,
    required this.totalSrv,
    this.isMissingOnServer = false,
    this.isMissingLocally = false,
  });

  bool get isMismatch =>
      isMissingOnServer ||
      isMissingLocally ||
      (qtyLoc - qtySrv).abs() > 0.01 ||
      (fQtyLoc - fQtySrv).abs() > 0.01 ||
      (discPercentLoc - discPercentSrv).abs() > 0.01 ||
      (totalLoc - totalSrv).abs() > 0.01;
}

class DiscrepancyRecord {
  final String category;
  final String primaryKey;
  final String title;
  final String date;
  final String customer;
  final String agent;
  final String paymentMode;
  final String doctor;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> serverData;
  final List<DiscrepancyField> fields;
  final List<DiscrepancyItemRow> itemRows;
  final bool isMissingLocally;
  final bool isMissingOnServer;

  DiscrepancyRecord({
    required this.category,
    required this.primaryKey,
    required this.title,
    required this.date,
    this.customer = '-',
    this.agent = 'Admin',
    this.paymentMode = 'CASH',
    this.doctor = '1',
    required this.localData,
    required this.serverData,
    required this.fields,
    this.itemRows = const [],
    this.isMissingLocally = false,
    this.isMissingOnServer = false,
  });

  bool get hasDiscrepancy =>
      isMissingLocally ||
      isMissingOnServer ||
      fields.any((f) => f.isMismatch) ||
      itemRows.any((i) => i.isMismatch);
}

class DiscrepancyAuditService {
  static final DiscrepancyAuditService instance = DiscrepancyAuditService._internal();
  DiscrepancyAuditService._internal();

  static String _normalizeKey(String raw) {
    var clean = raw.trim().toUpperCase();

    // Preserve full primary keys (including terminal prefixes like T1-, T2-).
    // Only strip financial year prefix if present (e.g., 2026-27_T2-7 -> T2-7).
    if (clean.contains('_')) {
      clean = clean.split('_').last.trim();
    }

    return clean;
  }

  num _parseNum(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val;
    return num.tryParse(val.toString().trim()) ?? 0;
  }

  Future<List<DiscrepancyRecord>> fetchDiscrepancies({
    required String categoryKey,
    DateTimeRange? dateRange,
    bool showOnlyDiscrepancies = true,
    int limit = 500,
  }) async {
    final config = ServerConfigService.instance;
    if (config.supabaseUrl.trim().isEmpty || config.supabaseAnonKey.trim().isEmpty) {
      debugPrint('DiscrepancyAuditService: Missing Supabase URL or Anon Key.');
      return [];
    }

    try {
      switch (categoryKey) {
        case 'sales_invoices':
          return await _auditSalesInvoices(dateRange: dateRange, limit: limit, showOnlyDiscrepancies: showOnlyDiscrepancies);
        case 'purchase_entries':
          return await _auditPurchaseEntries(dateRange: dateRange, limit: limit, showOnlyDiscrepancies: showOnlyDiscrepancies);
        case 'stock_batches':
          return await _auditStockBatches(limit: limit, showOnlyDiscrepancies: showOnlyDiscrepancies);
        case 'sales_return_invoices':
          return await _auditSalesReturns(dateRange: dateRange, limit: limit, showOnlyDiscrepancies: showOnlyDiscrepancies);
        case 'purchase_return_entries':
          return await _auditPurchaseReturns(dateRange: dateRange, limit: limit, showOnlyDiscrepancies: showOnlyDiscrepancies);
        case 'product_master':
          return await _auditProductMaster(limit: limit, showOnlyDiscrepancies: showOnlyDiscrepancies);
        default:
          return await _auditGenericTable(categoryKey, limit: limit, showOnlyDiscrepancies: showOnlyDiscrepancies);
      }
    } catch (e, stack) {
      debugPrint('DiscrepancyAuditService error [$categoryKey]: $e\n$stack');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchServerRecords(String endpoint, {int limit = 500}) async {
    try {
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final uri = Uri.parse('$cleanUrl/rest/v1/$endpoint?select=*&limit=$limit');
      
      final headers = {
        'apikey': config.supabaseAnonKey.trim(),
        'Authorization': 'Bearer ${config.supabaseAnonKey.trim()}',
        'Content-Type': 'application/json',
      };

      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 || res.statusCode == 206) {
        final List list = jsonDecode(res.body) as List;
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        debugPrint('Supabase REST error [${res.statusCode}] for $endpoint: ${res.body}');
      }
    } catch (e) {
      debugPrint('Error fetching server records for $endpoint: $e');
    }
    return [];
  }

  Future<List<DiscrepancyItemRow>> _fetchSalesItemRows(String key) async {
    try {
      final db = await DbHelper.instance.database;
      final localItems = await db.rawQuery(
        'SELECT * FROM sales_items WHERE invoice_no = ? OR invoice_no LIKE ?',
        [key, '%_$key'],
      );

      var serverItems = await _fetchServerRecords(
        'sales_items?or=(invoice_no.eq.${Uri.encodeComponent(key)},invoice_no.ilike.*_${Uri.encodeComponent(key)})',
      );
      if (serverItems.isEmpty) {
        serverItems = await _fetchServerRecords(
          'sales_items?invoice_no=eq.${Uri.encodeComponent(key)}',
        );
      }

      final localMap = <String, Map<String, dynamic>>{};
      for (var r in localItems) {
        final pName = (r['product_name'] ?? r['name'] ?? r['product'] ?? '').toString().trim().toUpperCase();
        final batch = (r['batch_number'] ?? r['batch_no'] ?? r['batch'] ?? '').toString().trim().toUpperCase();
        final itemKey = '${pName}_$batch';
        localMap[itemKey] = Map<String, dynamic>.from(r);
      }

      final serverMap = <String, Map<String, dynamic>>{};
      for (var r in serverItems) {
        final pName = (r['product_name'] ?? r['name'] ?? r['product'] ?? '').toString().trim().toUpperCase();
        final batch = (r['batch_number'] ?? r['batch_no'] ?? r['batch'] ?? '').toString().trim().toUpperCase();
        final itemKey = '${pName}_$batch';
        serverMap[itemKey] = r;
      }

      final allItemKeys = {...localMap.keys, ...serverMap.keys};
      final matchedServerKeys = <String>{};
      final rows = <DiscrepancyItemRow>[];

      for (var k in allItemKeys) {
        var loc = localMap[k];
        var srv = serverMap[k];

        if (srv != null) {
          matchedServerKeys.add(k);
        }

        // Smart fallback by product name if exact batch key wasn't matched directly
        if (loc != null && srv == null) {
          final pName = (loc['product_name'] ?? loc['name'] ?? '').toString().trim().toUpperCase();
          final candidateSrvKey = serverMap.keys.firstWhere(
            (sk) => sk.startsWith('${pName}_') && !matchedServerKeys.contains(sk),
            orElse: () => '',
          );
          if (candidateSrvKey.isNotEmpty) {
            srv = serverMap[candidateSrvKey];
            matchedServerKeys.add(candidateSrvKey);
          }
        }

        final pName = (srv?['product_name'] ?? loc?['product_name'] ?? 'Item').toString();
        final batch = (srv?['batch_number'] ?? srv?['batch_no'] ?? loc?['batch_number'] ?? loc?['batch_no'] ?? '-').toString();
        final expiry = (srv?['expiry_date'] ?? srv?['exp_date'] ?? loc?['expiry_date'] ?? loc?['exp_date'] ?? '-').toString();

        final qLoc = _parseNum(loc?['quantity'] ?? loc?['qty']);
        final qSrv = _parseNum(srv?['quantity'] ?? srv?['qty']);
        final fQtyLoc = _parseNum(loc?['f_qty'] ?? loc?['free_qty']);
        final fQtySrv = _parseNum(srv?['f_qty'] ?? srv?['free_qty']);
        final mrpLoc = _parseNum(loc?['mrp']);
        final mrpSrv = _parseNum(srv?['mrp']);
        final rateLoc = _parseNum(loc?['s_rate'] ?? loc?['sale_rate'] ?? loc?['unit_price'] ?? loc?['taxable_sp'] ?? loc?['mrp']);
        final rateSrv = _parseNum(srv?['s_rate'] ?? srv?['sale_rate'] ?? srv?['unit_price'] ?? srv?['taxable_sp'] ?? srv?['mrp']);
        final discLoc = _parseNum(loc?['disc_percent']);
        final discSrv = _parseNum(srv?['disc_percent']);
        final gstLoc = _parseNum(loc?['gst_percent'] ?? loc?['tax_percent']);
        final gstSrv = _parseNum(srv?['gst_percent'] ?? srv?['tax_percent']);

        var totLoc = _parseNum(loc?['total'] ?? loc?['total_amount'] ?? loc?['net_amount']);
        if (totLoc == 0 && qLoc > 0 && rateLoc > 0) {
          totLoc = qLoc * rateLoc;
          if (discLoc > 0) totLoc -= (totLoc * discLoc / 100);
        }

        var totSrv = _parseNum(srv?['total'] ?? srv?['total_amount'] ?? srv?['net_amount']);
        if (totSrv == 0 && qSrv > 0 && rateSrv > 0) {
          totSrv = qSrv * rateSrv;
          if (discSrv > 0) totSrv -= (totSrv * discSrv / 100);
        }

        rows.add(DiscrepancyItemRow(
          productName: pName,
          batchNumber: batch,
          expiryDate: expiry,
          qtyLoc: qLoc,
          qtySrv: qSrv,
          fQtyLoc: fQtyLoc,
          fQtySrv: fQtySrv,
          mrpLoc: mrpLoc,
          mrpSrv: mrpSrv,
          rateLoc: rateLoc,
          rateSrv: rateSrv,
          discPercentLoc: discLoc,
          discPercentSrv: discSrv,
          taxPercentLoc: gstLoc,
          taxPercentSrv: gstSrv,
          totalLoc: totLoc,
          totalSrv: totSrv,
          isMissingLocally: loc == null && srv != null,
          isMissingOnServer: loc != null && srv == null,
        ));
      }
      return rows;
    } catch (e) {
      debugPrint('Error fetching sales item rows: $e');
    }
    return [];
  }

  List<DiscrepancyItemRow> _buildSalesItemRowsFromMaps(
    String key,
    List<Map<String, dynamic>>? localItems,
    List<Map<String, dynamic>>? serverItems,
  ) {
    if ((localItems == null || localItems.isEmpty) && (serverItems == null || serverItems.isEmpty)) {
      return [];
    }

    final localMap = <String, Map<String, dynamic>>{};
    for (var r in (localItems ?? [])) {
      final pName = (r['product_name'] ?? r['name'] ?? r['product'] ?? '').toString().trim().toUpperCase();
      final batch = (r['batch_number'] ?? r['batch_no'] ?? r['batch'] ?? '').toString().trim().toUpperCase();
      final itemKey = '${pName}_$batch';
      localMap[itemKey] = Map<String, dynamic>.from(r);
    }

    final serverMap = <String, Map<String, dynamic>>{};
    for (var r in (serverItems ?? [])) {
      final pName = (r['product_name'] ?? r['name'] ?? r['product'] ?? '').toString().trim().toUpperCase();
      final batch = (r['batch_number'] ?? r['batch_no'] ?? r['batch'] ?? '').toString().trim().toUpperCase();
      final itemKey = '${pName}_$batch';
      serverMap[itemKey] = r;
    }

    final allItemKeys = {...localMap.keys, ...serverMap.keys};
    final matchedServerKeys = <String>{};
    final rows = <DiscrepancyItemRow>[];

    for (var k in allItemKeys) {
      var loc = localMap[k];
      var srv = serverMap[k];

      if (srv != null) {
        matchedServerKeys.add(k);
      }

      // Smart fallback by product name if exact batch key wasn't matched directly
      if (loc != null && srv == null) {
        final pName = (loc['product_name'] ?? loc['name'] ?? '').toString().trim().toUpperCase();
        final candidateSrvKey = serverMap.keys.firstWhere(
          (sk) => sk.startsWith('${pName}_') && !matchedServerKeys.contains(sk),
          orElse: () => '',
        );
        if (candidateSrvKey.isNotEmpty) {
          srv = serverMap[candidateSrvKey];
          matchedServerKeys.add(candidateSrvKey);
        }
      }

      final pName = (srv?['product_name'] ?? loc?['product_name'] ?? 'Item').toString();
      final batch = (srv?['batch_number'] ?? srv?['batch_no'] ?? loc?['batch_number'] ?? loc?['batch_no'] ?? '-').toString();
      final expiry = (srv?['expiry_date'] ?? srv?['exp_date'] ?? loc?['expiry_date'] ?? loc?['exp_date'] ?? '-').toString();

      final qLoc = _parseNum(loc?['quantity'] ?? loc?['qty']);
      final qSrv = _parseNum(srv?['quantity'] ?? srv?['qty']);
      final fQtyLoc = _parseNum(loc?['f_qty'] ?? loc?['free_qty']);
      final fQtySrv = _parseNum(srv?['f_qty'] ?? srv?['free_qty']);
      final mrpLoc = _parseNum(loc?['mrp']);
      final mrpSrv = _parseNum(srv?['mrp']);
      final rateLoc = _parseNum(loc?['s_rate'] ?? loc?['sale_rate'] ?? loc?['unit_price'] ?? loc?['taxable_sp'] ?? loc?['mrp']);
      final rateSrv = _parseNum(srv?['s_rate'] ?? srv?['sale_rate'] ?? srv?['unit_price'] ?? srv?['taxable_sp'] ?? srv?['mrp']);
      final discLoc = _parseNum(loc?['disc_percent']);
      final discSrv = _parseNum(srv?['disc_percent']);
      final gstLoc = _parseNum(loc?['gst_percent'] ?? loc?['tax_percent']);
      final gstSrv = _parseNum(srv?['gst_percent'] ?? srv?['tax_percent']);

      var totLoc = _parseNum(loc?['total'] ?? loc?['total_amount'] ?? loc?['net_amount']);
      if (totLoc == 0 && qLoc > 0 && rateLoc > 0) {
        totLoc = qLoc * rateLoc;
        if (discLoc > 0) totLoc -= (totLoc * discLoc / 100);
      }

      var totSrv = _parseNum(srv?['total'] ?? srv?['total_amount'] ?? srv?['net_amount']);
      if (totSrv == 0 && qSrv > 0 && rateSrv > 0) {
        totSrv = qSrv * rateSrv;
        if (discSrv > 0) totSrv -= (totSrv * discSrv / 100);
      }

      rows.add(DiscrepancyItemRow(
        productName: pName,
        batchNumber: batch,
        expiryDate: expiry,
        qtyLoc: qLoc,
        qtySrv: qSrv,
        fQtyLoc: fQtyLoc,
        fQtySrv: fQtySrv,
        mrpLoc: mrpLoc,
        mrpSrv: mrpSrv,
        rateLoc: rateLoc,
        rateSrv: rateSrv,
        discPercentLoc: discLoc,
        discPercentSrv: discSrv,
        taxPercentLoc: gstLoc,
        taxPercentSrv: gstSrv,
        totalLoc: totLoc,
        totalSrv: totSrv,
        isMissingLocally: loc == null && srv != null,
        isMissingOnServer: loc != null && srv == null,
      ));
    }
    return rows;
  }

  // --- Audit Sales Invoices ---
  Future<List<DiscrepancyRecord>> _auditSalesInvoices({
    DateTimeRange? dateRange,
    int limit = 200,
    bool showOnlyDiscrepancies = true,
  }) async {
    final db = await DbHelper.instance.database;

    // Parallel execution for local & server queries
    final localRowsFuture = db.rawQuery(
      'SELECT * FROM sales_invoices ORDER BY rowid DESC LIMIT ?',
      [limit],
    );
    final serverRowsFuture = _fetchServerRecords('sales_invoices', limit: limit);
    final localItemsFuture = db.rawQuery('SELECT * FROM sales_items');
    final serverItemsFuture = _fetchServerRecords('sales_items', limit: limit * 4);

    final resultsList = await Future.wait([
      localRowsFuture,
      serverRowsFuture,
      localItemsFuture,
      serverItemsFuture,
    ]);

    final localRows = resultsList[0] as List<Map<String, dynamic>>;
    final serverRows = resultsList[1] as List<Map<String, dynamic>>;
    final localItems = resultsList[2] as List<Map<String, dynamic>>;
    final serverItems = resultsList[3] as List<Map<String, dynamic>>;

    // Map local items by normalized invoice key
    final localItemsByInv = <String, List<Map<String, dynamic>>>{};
    for (var r in localItems) {
      final rawInv = (r['invoice_no'] ?? '').toString();
      final k = _normalizeKey(rawInv);
      if (k.isNotEmpty) {
        localItemsByInv.putIfAbsent(k, () => []).add(r);
      }
    }

    // Map server items by normalized invoice key
    final serverItemsByInv = <String, List<Map<String, dynamic>>>{};
    for (var r in serverItems) {
      final rawInv = (r['invoice_no'] ?? '').toString();
      final k = _normalizeKey(rawInv);
      if (k.isNotEmpty) {
        serverItemsByInv.putIfAbsent(k, () => []).add(r);
      }
    }

    final localMap = <String, Map<String, dynamic>>{};
    for (var r in localRows) {
      final entryNo = (r['entry_no'] ?? r['invoice_no'] ?? '').toString().trim();
      final key = _normalizeKey(entryNo);
      if (key.isNotEmpty) localMap[key] = Map<String, dynamic>.from(r);
    }

    final serverMap = <String, Map<String, dynamic>>{};
    for (var r in serverRows) {
      final entryNo = (r['entry_no'] ?? r['invoice_no'] ?? '').toString().trim();
      final key = _normalizeKey(entryNo);
      if (key.isNotEmpty) serverMap[key] = r;
    }

    final allKeys = {...localMap.keys, ...serverMap.keys};
    final results = <DiscrepancyRecord>[];

    for (var k in allKeys) {
      final loc = localMap[k];
      final srv = serverMap[k];
      final itemRows = _buildSalesItemRowsFromMaps(k, localItemsByInv[k], serverItemsByInv[k]);

      if (loc == null && srv != null) {
        final custName = (srv['customer_name'] ?? srv['patient'] ?? 'Walk-in Customer').toString();
        final mob = (srv['mobile'] ?? srv['phone'] ?? '-').toString();
        final agent = (srv['agent'] ?? 'Admin').toString();
        final payMode = (srv['payment_mode'] ?? 'CASH').toString();
        final doc = (srv['doctor'] ?? '1').toString();
        final dateStr = (srv['date'] ?? srv['invoice_date'] ?? srv['created_at'] ?? '').toString();

        final subAmt = _parseNum(srv['subtotal'] ?? srv['sub_total']);
        final discAmt = _parseNum(srv['discount_amount'] ?? srv['discount']);
        final roundAmt = _parseNum(srv['round_off']);
        final netAmt = _parseNum(srv['net_amount'] ?? srv['grand_total'] ?? srv['total_amount']);

        results.add(DiscrepancyRecord(
          category: 'sales_invoices',
          primaryKey: k,
          title: 'Bill #${formatSaleDisplayNo(k)}',
          date: dateStr,
          customer: custName,
          agent: agent,
          paymentMode: payMode,
          doctor: doc,
          localData: {'mobile': mob},
          serverData: srv,
          itemRows: itemRows,
          fields: [
            DiscrepancyField(fieldName: 'customer', fieldLabel: 'Customer / Patient', localValue: 'MISSING LOCALLY', serverValue: custName),
            DiscrepancyField(fieldName: 'mobile', fieldLabel: 'Mobile / Phone', localValue: 'MISSING LOCALLY', serverValue: mob),
            DiscrepancyField(fieldName: 'agent', fieldLabel: 'Agent / Staff', localValue: 'MISSING LOCALLY', serverValue: agent),
            DiscrepancyField(fieldName: 'subtotal', fieldLabel: 'Sub Total', localValue: 0, serverValue: subAmt),
            DiscrepancyField(fieldName: 'discount_amount', fieldLabel: 'Discount', localValue: 0, serverValue: discAmt),
            DiscrepancyField(fieldName: 'round_off', fieldLabel: 'Round Off', localValue: 0, serverValue: roundAmt),
            DiscrepancyField(fieldName: 'net_amount', fieldLabel: 'Grand Total', localValue: 0, serverValue: netAmt),
          ],
          isMissingLocally: true,
        ));
      } else if (loc != null && srv == null) {
        final custName = (loc['customer_name'] ?? loc['patient'] ?? 'Walk-in Customer').toString();
        final mob = (loc['mobile'] ?? loc['phone'] ?? '-').toString();
        final agent = (loc['agent'] ?? 'Admin').toString();
        final payMode = (loc['payment_mode'] ?? 'CASH').toString();
        final doc = (loc['doctor'] ?? '1').toString();
        final dateStr = (loc['date'] ?? loc['invoice_date'] ?? '').toString();

        final subAmt = _parseNum(loc['subtotal'] ?? loc['sub_total']);
        final discAmt = _parseNum(loc['discount_amount'] ?? loc['discount']);
        final roundAmt = _parseNum(loc['round_off']);
        final netAmt = _parseNum(loc['net_amount'] ?? loc['grand_total'] ?? loc['total_amount']);

        results.add(DiscrepancyRecord(
          category: 'sales_invoices',
          primaryKey: k,
          title: 'Bill #${formatSaleDisplayNo(k)}',
          date: dateStr,
          customer: custName,
          agent: agent,
          paymentMode: payMode,
          doctor: doc,
          localData: loc,
          serverData: {'mobile': mob},
          itemRows: itemRows,
          fields: [
            DiscrepancyField(fieldName: 'customer', fieldLabel: 'Customer / Patient', localValue: custName, serverValue: 'NOT ON SERVER'),
            DiscrepancyField(fieldName: 'mobile', fieldLabel: 'Mobile / Phone', localValue: mob, serverValue: 'NOT ON SERVER'),
            DiscrepancyField(fieldName: 'agent', fieldLabel: 'Agent / Staff', localValue: agent, serverValue: 'NOT ON SERVER'),
            DiscrepancyField(fieldName: 'subtotal', fieldLabel: 'Sub Total', localValue: subAmt, serverValue: 0),
            DiscrepancyField(fieldName: 'discount_amount', fieldLabel: 'Discount', localValue: discAmt, serverValue: 0),
            DiscrepancyField(fieldName: 'round_off', fieldLabel: 'Round Off', localValue: roundAmt, serverValue: 0),
            DiscrepancyField(fieldName: 'net_amount', fieldLabel: 'Grand Total', localValue: netAmt, serverValue: 0),
          ],
          isMissingOnServer: true,
        ));
      } else if (loc != null && srv != null) {
        final custLoc = (loc['customer_name'] ?? loc['patient'] ?? 'Walk-in Customer').toString();
        final custSrv = (srv['customer_name'] ?? srv['patient'] ?? 'Walk-in Customer').toString();
        final mobLoc = (loc['mobile'] ?? loc['phone'] ?? '-').toString();
        final mobSrv = (srv['mobile'] ?? srv['phone'] ?? '-').toString();
        final agentLoc = (loc['agent'] ?? 'Admin').toString();
        final agentSrv = (srv['agent'] ?? 'Admin').toString();
        final payLoc = (loc['payment_mode'] ?? 'CASH').toString();
        final paySrv = (srv['payment_mode'] ?? 'CASH').toString();
        final docSrv = (srv['doctor'] ?? loc['doctor'] ?? '1').toString();
        final dateStr = (srv['date'] ?? loc['date'] ?? '').toString();

        final subLoc = _parseNum(loc['subtotal'] ?? loc['sub_total']);
        final subSrv = _parseNum(srv['subtotal'] ?? srv['sub_total']);
        final discLoc = _parseNum(loc['discount_amount'] ?? loc['discount']);
        final discSrv = _parseNum(srv['discount_amount'] ?? srv['discount']);
        final roundLoc = _parseNum(loc['round_off']);
        final roundSrv = _parseNum(srv['round_off']);
        final taxLoc = _parseNum(loc['tax_amount'] ?? loc['tax']);
        final taxSrv = _parseNum(srv['tax_amount'] ?? srv['tax']);
        final netLoc = _parseNum(loc['net_amount'] ?? loc['grand_total']);
        final netSrv = _parseNum(srv['net_amount'] ?? srv['grand_total']);

        final fields = [
          DiscrepancyField(fieldName: 'customer', fieldLabel: 'Customer / Patient', localValue: custLoc, serverValue: custSrv),
          DiscrepancyField(fieldName: 'mobile', fieldLabel: 'Mobile / Phone', localValue: mobLoc, serverValue: mobSrv),
          DiscrepancyField(fieldName: 'agent', fieldLabel: 'Agent / Staff', localValue: agentLoc, serverValue: agentSrv),
          DiscrepancyField(fieldName: 'payment_mode', fieldLabel: 'Payment Mode', localValue: payLoc, serverValue: paySrv),
          DiscrepancyField(fieldName: 'subtotal', fieldLabel: 'Sub Total', localValue: subLoc, serverValue: subSrv),
          DiscrepancyField(fieldName: 'discount_amount', fieldLabel: 'Discount', localValue: discLoc, serverValue: discSrv),
          DiscrepancyField(fieldName: 'round_off', fieldLabel: 'Round Off', localValue: roundLoc, serverValue: roundSrv),
          DiscrepancyField(fieldName: 'tax_amount', fieldLabel: 'Tax Amount', localValue: taxLoc, serverValue: taxSrv),
          DiscrepancyField(fieldName: 'net_amount', fieldLabel: 'Grand Total', localValue: netLoc, serverValue: netSrv),
          DiscrepancyField(
            fieldName: 'is_deleted',
            fieldLabel: 'Status',
            localValue: (loc['is_deleted'] == 1 ? 'Deleted' : 'Active'),
            serverValue: (srv['is_deleted'] == 1 || srv['is_deleted'] == true ? 'Deleted' : 'Active'),
          ),
        ];

        final rec = DiscrepancyRecord(
          category: 'sales_invoices',
          primaryKey: k,
          title: 'Bill #${formatSaleDisplayNo(k)}',
          date: dateStr,
          customer: custSrv,
          agent: agentSrv,
          paymentMode: paySrv,
          doctor: docSrv,
          localData: loc,
          serverData: srv,
          fields: fields,
          itemRows: itemRows,
        );

        if (!showOnlyDiscrepancies || rec.hasDiscrepancy) {
          results.add(rec);
        }
      }
    }

    return results;
  }

  // --- Audit Purchase Entries ---
  Future<List<DiscrepancyRecord>> _auditPurchaseEntries({
    DateTimeRange? dateRange,
    int limit = 500,
    bool showOnlyDiscrepancies = true,
  }) async {
    final db = await DbHelper.instance.database;

    final localRowsFuture = db.rawQuery(
      'SELECT * FROM purchase_entries ORDER BY rowid DESC LIMIT ?',
      [limit],
    );
    final serverRowsFuture = _fetchServerRecords('purchase_entries', limit: limit);
    final localItemsFuture = db.rawQuery('SELECT * FROM purchase_items');
    final serverItemsFuture = _fetchServerRecords('purchase_items', limit: limit * 6);

    final resultsList = await Future.wait([
      localRowsFuture,
      serverRowsFuture,
      localItemsFuture,
      serverItemsFuture,
    ]);

    final localRows = resultsList[0] as List<Map<String, dynamic>>;
    final serverRows = resultsList[1] as List<Map<String, dynamic>>;
    final localItems = resultsList[2] as List<Map<String, dynamic>>;
    final serverItems = resultsList[3] as List<Map<String, dynamic>>;

    // Map local purchase items by normalized entry key
    final localItemsByEntry = <String, List<Map<String, dynamic>>>{};
    for (var r in localItems) {
      final rawKey = (r['entry_no'] ?? r['invoice_no'] ?? '').toString();
      final k = _normalizeKey(rawKey);
      if (k.isNotEmpty) {
        localItemsByEntry.putIfAbsent(k, () => []).add(r);
      }
    }

    // Map server purchase items by normalized entry key
    final serverItemsByEntry = <String, List<Map<String, dynamic>>>{};
    for (var r in serverItems) {
      final rawKey = (r['entry_no'] ?? r['invoice_no'] ?? '').toString();
      final k = _normalizeKey(rawKey);
      if (k.isNotEmpty) {
        serverItemsByEntry.putIfAbsent(k, () => []).add(r);
      }
    }

    final localMap = <String, Map<String, dynamic>>{};
    for (var r in localRows) {
      final key = _normalizeKey((r['entry_no'] ?? '').toString());
      if (key.isNotEmpty) localMap[key] = Map<String, dynamic>.from(r);
    }

    final serverMap = <String, Map<String, dynamic>>{};
    for (var r in serverRows) {
      final key = _normalizeKey((r['entry_no'] ?? '').toString());
      if (key.isNotEmpty) serverMap[key] = r;
    }

    final allKeys = {...localMap.keys, ...serverMap.keys};
    final results = <DiscrepancyRecord>[];

    for (var k in allKeys) {
      final loc = localMap[k];
      final srv = serverMap[k];
      final itemRows = _buildSalesItemRowsFromMaps(k, localItemsByEntry[k], serverItemsByEntry[k]);

      if (loc == null && srv != null) {
        final supplier = (srv['supplier_name'] ?? 'Supplier').toString();
        final doneBy = (srv['done_by'] ?? 'Admin').toString();
        final dateStr = (srv['date'] ?? '').toString();
        final netAmt = _parseNum(srv['net_amount'] ?? srv['inv_total'] ?? srv['grand_total']);
        final subTotal = _parseNum(srv['subtotal'] ?? srv['sub_total']);
        final discAmt = _parseNum(srv['discount_amount'] ?? srv['discount']);
        final roundOff = _parseNum(srv['round_off']);

        results.add(DiscrepancyRecord(
          category: 'purchase_entries',
          primaryKey: k,
          title: 'Entry #$k',
          date: dateStr,
          customer: supplier,
          agent: doneBy,
          paymentMode: (srv['payment_mode'] ?? 'CREDIT').toString(),
          localData: {},
          serverData: srv,
          itemRows: itemRows,
          fields: [
            DiscrepancyField(fieldName: 'supplier_name', fieldLabel: 'Supplier', localValue: 'MISSING LOCALLY', serverValue: supplier),
            DiscrepancyField(fieldName: 'done_by', fieldLabel: 'Purchased By', localValue: 'MISSING LOCALLY', serverValue: doneBy),
            DiscrepancyField(fieldName: 'subtotal', fieldLabel: 'Sub Total', localValue: 0, serverValue: subTotal),
            DiscrepancyField(fieldName: 'discount_amount', fieldLabel: 'Discount', localValue: 0, serverValue: discAmt),
            DiscrepancyField(fieldName: 'round_off', fieldLabel: 'Round Off', localValue: 0, serverValue: roundOff),
            DiscrepancyField(fieldName: 'net_amount', fieldLabel: 'Grand Total', localValue: 0, serverValue: netAmt),
          ],
          isMissingLocally: true,
        ));
      } else if (loc != null && srv == null) {
        final supplier = (loc['supplier_name'] ?? 'Supplier').toString();
        final doneBy = (loc['done_by'] ?? 'Admin').toString();
        final dateStr = (loc['date'] ?? '').toString();
        final netAmt = _parseNum(loc['inv_total'] ?? loc['grand_total'] ?? loc['net_amount']);
        final subTotal = _parseNum(loc['sub_total'] ?? loc['subtotal']);
        final discAmt = _parseNum(loc['discount'] ?? loc['discount_amount']);
        final roundOff = _parseNum(loc['round_off']);

        results.add(DiscrepancyRecord(
          category: 'purchase_entries',
          primaryKey: k,
          title: 'Entry #$k',
          date: dateStr,
          customer: supplier,
          agent: doneBy,
          paymentMode: (loc['payment_mode'] ?? 'CREDIT').toString(),
          localData: loc,
          serverData: {},
          itemRows: itemRows,
          fields: [
            DiscrepancyField(fieldName: 'supplier_name', fieldLabel: 'Supplier', localValue: supplier, serverValue: 'NOT ON SERVER'),
            DiscrepancyField(fieldName: 'done_by', fieldLabel: 'Purchased By', localValue: doneBy, serverValue: 'NOT ON SERVER'),
            DiscrepancyField(fieldName: 'subtotal', fieldLabel: 'Sub Total', localValue: subTotal, serverValue: 0),
            DiscrepancyField(fieldName: 'discount_amount', fieldLabel: 'Discount', localValue: discAmt, serverValue: 0),
            DiscrepancyField(fieldName: 'round_off', fieldLabel: 'Round Off', localValue: roundOff, serverValue: 0),
            DiscrepancyField(fieldName: 'net_amount', fieldLabel: 'Grand Total', localValue: netAmt, serverValue: 0),
          ],
          isMissingOnServer: true,
        ));
      } else if (loc != null && srv != null) {
        final supplierLoc = (loc['supplier_name'] ?? 'Supplier').toString();
        final supplierSrv = (srv['supplier_name'] ?? 'Supplier').toString();
        final doneByLoc = (loc['done_by'] ?? 'Admin').toString();
        final doneBySrv = (srv['done_by'] ?? 'Admin').toString();

        final subLoc = _parseNum(loc['sub_total'] ?? loc['subtotal']);
        final subSrv = _parseNum(srv['subtotal'] ?? srv['sub_total']);

        final discLoc = _parseNum(loc['discount'] ?? loc['discount_amount']);
        final discSrv = _parseNum(srv['discount_amount'] ?? srv['discount']);

        final roundLoc = _parseNum(loc['round_off']);
        final roundSrv = _parseNum(srv['round_off']);

        final netLoc = _parseNum(loc['inv_total'] ?? loc['grand_total'] ?? loc['net_amount']);
        final netSrv = _parseNum(srv['net_amount'] ?? srv['inv_total'] ?? srv['grand_total']);

        final fields = [
          DiscrepancyField(fieldName: 'supplier_name', fieldLabel: 'Supplier', localValue: supplierLoc, serverValue: supplierSrv),
          DiscrepancyField(fieldName: 'sup_inv_no', fieldLabel: 'Vendor Inv #', localValue: loc['sup_inv_no'], serverValue: srv['sup_inv_no']),
          DiscrepancyField(fieldName: 'done_by', fieldLabel: 'Purchased By', localValue: doneByLoc, serverValue: doneBySrv),
          DiscrepancyField(fieldName: 'subtotal', fieldLabel: 'Sub Total', localValue: subLoc, serverValue: subSrv),
          DiscrepancyField(fieldName: 'discount_amount', fieldLabel: 'Discount', localValue: discLoc, serverValue: discSrv),
          DiscrepancyField(fieldName: 'round_off', fieldLabel: 'Round Off', localValue: roundLoc, serverValue: roundSrv),
          DiscrepancyField(fieldName: 'net_amount', fieldLabel: 'Grand Total', localValue: netLoc, serverValue: netSrv),
          DiscrepancyField(
            fieldName: 'is_deleted',
            fieldLabel: 'Status',
            localValue: (loc['is_deleted'] == 1 ? 'Deleted' : 'Active'),
            serverValue: (srv['is_deleted'] == 1 || srv['is_deleted'] == true ? 'Deleted' : 'Active'),
          ),
        ];

        final rec = DiscrepancyRecord(
          category: 'purchase_entries',
          primaryKey: k,
          title: 'Entry #$k',
          date: (srv['date'] ?? loc['date'] ?? '').toString(),
          customer: supplierSrv,
          agent: doneBySrv,
          paymentMode: (srv['payment_mode'] ?? loc['payment_mode'] ?? 'CREDIT').toString(),
          localData: loc,
          serverData: srv,
          itemRows: itemRows,
          fields: fields,
        );

        if (!showOnlyDiscrepancies || rec.hasDiscrepancy) {
          results.add(rec);
        }
      }
    }

    return results;
  }

  // --- Audit Stock Batches ---
  Future<List<DiscrepancyRecord>> _auditStockBatches({
    int limit = 500,
    bool showOnlyDiscrepancies = true,
  }) async {
    final db = await DbHelper.instance.database;
    final localRows = await db.rawQuery(
      'SELECT * FROM stock_batches ORDER BY rowid DESC LIMIT ?',
      [limit],
    );

    final serverRows = await _fetchServerRecords('stock_batches', limit: limit);

    final localMap = <String, Map<String, dynamic>>{};
    for (var r in localRows) {
      final key = '${r['product_name']}_${r['batch_no']}'.trim().toUpperCase();
      if (key.isNotEmpty) localMap[key] = Map<String, dynamic>.from(r);
    }

    final serverMap = <String, Map<String, dynamic>>{};
    for (var r in serverRows) {
      final key = '${r['product_name']}_${r['batch_no']}'.trim().toUpperCase();
      if (key.isNotEmpty) serverMap[key] = r;
    }

    final allKeys = {...localMap.keys, ...serverMap.keys};
    final results = <DiscrepancyRecord>[];

    for (var k in allKeys) {
      final loc = localMap[k];
      final srv = serverMap[k];

      if (loc == null && srv != null) {
        results.add(DiscrepancyRecord(
          category: 'stock_batches',
          primaryKey: k,
          title: '${srv['product_name'] ?? 'Product'}',
          date: (srv['expiry_date'] ?? '').toString(),
          customer: 'Batch: ${srv['batch_no'] ?? '-'}',
          agent: 'Stock',
          localData: {},
          serverData: srv,
          fields: [
            DiscrepancyField(fieldName: 'quantity', fieldLabel: 'Stock Qty', localValue: 'MISSING LOCALLY', serverValue: srv['quantity']),
          ],
          isMissingLocally: true,
        ));
      } else if (loc != null && srv == null) {
        results.add(DiscrepancyRecord(
          category: 'stock_batches',
          primaryKey: k,
          title: '${loc['product_name'] ?? 'Product'}',
          date: (loc['expiry_date'] ?? '').toString(),
          customer: 'Batch: ${loc['batch_no'] ?? '-'}',
          agent: 'Stock',
          localData: loc,
          serverData: {},
          fields: [
            DiscrepancyField(fieldName: 'quantity', fieldLabel: 'Stock Qty', localValue: loc['quantity'], serverValue: 'NOT ON SERVER'),
          ],
          isMissingOnServer: true,
        ));
      } else if (loc != null && srv != null) {
        final fields = [
          DiscrepancyField(fieldName: 'product_name', fieldLabel: 'Product', localValue: loc['product_name'], serverValue: srv['product_name']),
          DiscrepancyField(fieldName: 'batch_no', fieldLabel: 'Batch No', localValue: loc['batch_no'], serverValue: srv['batch_no']),
          DiscrepancyField(fieldName: 'expiry_date', fieldLabel: 'Expiry', localValue: loc['expiry_date'], serverValue: srv['expiry_date']),
          DiscrepancyField(fieldName: 'quantity', fieldLabel: 'Stock Qty', localValue: loc['quantity'], serverValue: srv['quantity']),
          DiscrepancyField(fieldName: 'mrp', fieldLabel: 'MRP', localValue: loc['mrp'], serverValue: srv['mrp']),
          DiscrepancyField(fieldName: 'rate', fieldLabel: 'Rate', localValue: loc['rate'], serverValue: srv['rate']),
        ];

        final rec = DiscrepancyRecord(
          category: 'stock_batches',
          primaryKey: k,
          title: '${srv['product_name'] ?? loc['product_name'] ?? 'Product'}',
          date: (srv['expiry_date'] ?? loc['expiry_date'] ?? '').toString(),
          customer: 'Batch: ${srv['batch_no'] ?? loc['batch_no'] ?? '-'}',
          agent: 'Stock',
          localData: loc,
          serverData: srv,
          fields: fields,
        );

        if (!showOnlyDiscrepancies || rec.hasDiscrepancy) {
          results.add(rec);
        }
      }
    }

    return results;
  }

  // --- Audit Sales Returns ---
  Future<List<DiscrepancyRecord>> _auditSalesReturns({
    DateTimeRange? dateRange,
    int limit = 500,
    bool showOnlyDiscrepancies = true,
  }) async {
    final db = await DbHelper.instance.database;

    final localRowsFuture = db.rawQuery(
      'SELECT * FROM sales_return_invoices ORDER BY rowid DESC LIMIT ?',
      [limit],
    );
    final serverRowsFuture = _fetchServerRecords('sales_return_invoices', limit: limit);
    final localItemsFuture = db.rawQuery('SELECT * FROM sales_return_items');
    final serverItemsFuture = _fetchServerRecords('sales_return_items', limit: limit * 6);

    final resultsList = await Future.wait([
      localRowsFuture,
      serverRowsFuture,
      localItemsFuture,
      serverItemsFuture,
    ]);

    final localRows = resultsList[0] as List<Map<String, dynamic>>;
    final serverRows = resultsList[1] as List<Map<String, dynamic>>;
    final localItems = resultsList[2] as List<Map<String, dynamic>>;
    final serverItems = resultsList[3] as List<Map<String, dynamic>>;

    final localItemsByReturn = <String, List<Map<String, dynamic>>>{};
    for (var r in localItems) {
      final rawKey = (r['return_no'] ?? r['invoice_no'] ?? r['entry_no'] ?? '').toString();
      final k = _normalizeKey(rawKey);
      if (k.isNotEmpty) {
        localItemsByReturn.putIfAbsent(k, () => []).add(r);
      }
    }

    final serverItemsByReturn = <String, List<Map<String, dynamic>>>{};
    for (var r in serverItems) {
      final rawKey = (r['return_no'] ?? r['invoice_no'] ?? r['entry_no'] ?? '').toString();
      final k = _normalizeKey(rawKey);
      if (k.isNotEmpty) {
        serverItemsByReturn.putIfAbsent(k, () => []).add(r);
      }
    }

    final localMap = <String, Map<String, dynamic>>{};
    for (var r in localRows) {
      final key = _normalizeKey((r['entry_no'] ?? '').toString());
      if (key.isNotEmpty) localMap[key] = Map<String, dynamic>.from(r);
    }

    final serverMap = <String, Map<String, dynamic>>{};
    for (var r in serverRows) {
      final key = _normalizeKey((r['entry_no'] ?? '').toString());
      if (key.isNotEmpty) serverMap[key] = r;
    }

    final allKeys = {...localMap.keys, ...serverMap.keys};
    final results = <DiscrepancyRecord>[];

    for (var k in allKeys) {
      final loc = localMap[k];
      final srv = serverMap[k];
      final itemRows = _buildSalesItemRowsFromMaps(k, localItemsByReturn[k], serverItemsByReturn[k]);

      if (loc == null && srv != null) {
        results.add(DiscrepancyRecord(
          category: 'sales_return_invoices',
          primaryKey: k,
          title: 'Return #$k',
          date: (srv['date'] ?? '').toString(),
          customer: (srv['patient'] ?? srv['customer_acc'] ?? 'Customer').toString(),
          agent: 'Return',
          localData: {},
          serverData: srv,
          itemRows: itemRows,
          fields: [
            DiscrepancyField(fieldName: 'grand_total', fieldLabel: 'Return Total', localValue: 'MISSING LOCALLY', serverValue: srv['grand_total']),
          ],
          isMissingLocally: true,
        ));
      } else if (loc != null && srv == null) {
        results.add(DiscrepancyRecord(
          category: 'sales_return_invoices',
          primaryKey: k,
          title: 'Return #$k',
          date: (loc['date'] ?? '').toString(),
          customer: (loc['patient'] ?? loc['customer_acc'] ?? 'Customer').toString(),
          agent: 'Return',
          localData: loc,
          serverData: {},
          itemRows: itemRows,
          fields: [
            DiscrepancyField(fieldName: 'grand_total', fieldLabel: 'Return Total', localValue: loc['grand_total'], serverValue: 'NOT ON SERVER'),
          ],
          isMissingOnServer: true,
        ));
      } else if (loc != null && srv != null) {
        final fields = [
          DiscrepancyField(fieldName: 'original_invoice_no', fieldLabel: 'Original Bill', localValue: loc['original_invoice_no'], serverValue: srv['original_invoice_no']),
          DiscrepancyField(fieldName: 'grand_total', fieldLabel: 'Return Total', localValue: _parseNum(loc['grand_total']), serverValue: _parseNum(srv['grand_total'])),
          DiscrepancyField(
            fieldName: 'is_deleted',
            fieldLabel: 'Status',
            localValue: (loc['is_deleted'] == 1 ? 'Deleted' : 'Active'),
            serverValue: (srv['is_deleted'] == 1 || srv['is_deleted'] == true ? 'Deleted' : 'Active'),
          ),
        ];

        final rec = DiscrepancyRecord(
          category: 'sales_return_invoices',
          primaryKey: k,
          title: 'Return #$k',
          date: (srv['date'] ?? loc['date'] ?? '').toString(),
          customer: (srv['patient'] ?? srv['customer_acc'] ?? 'Customer').toString(),
          agent: 'Return',
          localData: loc,
          serverData: srv,
          itemRows: itemRows,
          fields: fields,
        );

        if (!showOnlyDiscrepancies || rec.hasDiscrepancy) {
          results.add(rec);
        }
      }
    }

    return results;
  }

  // --- Audit Purchase Returns ---
  Future<List<DiscrepancyRecord>> _auditPurchaseReturns({
    DateTimeRange? dateRange,
    int limit = 500,
    bool showOnlyDiscrepancies = true,
  }) async {
    final db = await DbHelper.instance.database;

    final localRowsFuture = db.rawQuery(
      'SELECT * FROM purchase_return_entries ORDER BY rowid DESC LIMIT ?',
      [limit],
    );
    final serverRowsFuture = _fetchServerRecords('purchase_return_entries', limit: limit);
    final localItemsFuture = db.rawQuery('SELECT * FROM purchase_return_items');
    final serverItemsFuture = _fetchServerRecords('purchase_return_items', limit: limit * 6);

    final resultsList = await Future.wait([
      localRowsFuture,
      serverRowsFuture,
      localItemsFuture,
      serverItemsFuture,
    ]);

    final localRows = resultsList[0] as List<Map<String, dynamic>>;
    final serverRows = resultsList[1] as List<Map<String, dynamic>>;
    final localItems = resultsList[2] as List<Map<String, dynamic>>;
    final serverItems = resultsList[3] as List<Map<String, dynamic>>;

    final localItemsByReturn = <String, List<Map<String, dynamic>>>{};
    for (var r in localItems) {
      final rawKey = (r['entry_no'] ?? r['return_no'] ?? '').toString();
      final k = _normalizeKey(rawKey);
      if (k.isNotEmpty) {
        localItemsByReturn.putIfAbsent(k, () => []).add(r);
      }
    }

    final serverItemsByReturn = <String, List<Map<String, dynamic>>>{};
    for (var r in serverItems) {
      final rawKey = (r['entry_no'] ?? r['return_no'] ?? '').toString();
      final k = _normalizeKey(rawKey);
      if (k.isNotEmpty) {
        serverItemsByReturn.putIfAbsent(k, () => []).add(r);
      }
    }

    final localMap = <String, Map<String, dynamic>>{};
    for (var r in localRows) {
      final key = _normalizeKey((r['entry_no'] ?? '').toString());
      if (key.isNotEmpty) localMap[key] = Map<String, dynamic>.from(r);
    }

    final serverMap = <String, Map<String, dynamic>>{};
    for (var r in serverRows) {
      final key = _normalizeKey((r['entry_no'] ?? '').toString());
      if (key.isNotEmpty) serverMap[key] = r;
    }

    final allKeys = {...localMap.keys, ...serverMap.keys};
    final results = <DiscrepancyRecord>[];

    for (var k in allKeys) {
      final loc = localMap[k];
      final srv = serverMap[k];
      final itemRows = _buildSalesItemRowsFromMaps(k, localItemsByReturn[k], serverItemsByReturn[k]);

      if (loc == null && srv != null) {
        results.add(DiscrepancyRecord(
          category: 'purchase_return_entries',
          primaryKey: k,
          title: 'Return #$k',
          date: (srv['date'] ?? '').toString(),
          customer: (srv['supplier_name'] ?? 'Supplier').toString(),
          agent: 'Purchase Return',
          localData: {},
          serverData: srv,
          itemRows: itemRows,
          fields: [
            DiscrepancyField(fieldName: 'net_amount', fieldLabel: 'Return Net', localValue: 'MISSING LOCALLY', serverValue: srv['net_amount'] ?? srv['grand_total']),
          ],
          isMissingLocally: true,
        ));
      } else if (loc != null && srv == null) {
        results.add(DiscrepancyRecord(
          category: 'purchase_return_entries',
          primaryKey: k,
          title: 'Return #$k',
          date: (loc['date'] ?? '').toString(),
          customer: (loc['supplier_name'] ?? 'Supplier').toString(),
          agent: 'Purchase Return',
          localData: loc,
          serverData: {},
          itemRows: itemRows,
          fields: [
            DiscrepancyField(fieldName: 'net_amount', fieldLabel: 'Return Net', localValue: loc['net_amount'] ?? loc['grand_total'], serverValue: 'NOT ON SERVER'),
          ],
          isMissingOnServer: true,
        ));
      } else if (loc != null && srv != null) {
        final netLoc = _parseNum(loc['grand_total'] ?? loc['net_amount']);
        final netSrv = _parseNum(srv['net_amount'] ?? srv['grand_total']);

        final fields = [
          DiscrepancyField(fieldName: 'supplier_name', fieldLabel: 'Supplier', localValue: loc['supplier_name'], serverValue: srv['supplier_name']),
          DiscrepancyField(fieldName: 'net_amount', fieldLabel: 'Return Net', localValue: netLoc, serverValue: netSrv),
          DiscrepancyField(
            fieldName: 'is_deleted',
            fieldLabel: 'Status',
            localValue: (loc['is_deleted'] == 1 ? 'Deleted' : 'Active'),
            serverValue: (srv['is_deleted'] == 1 || srv['is_deleted'] == true ? 'Deleted' : 'Active'),
          ),
        ];

        final rec = DiscrepancyRecord(
          category: 'purchase_return_entries',
          primaryKey: k,
          title: 'Return #$k',
          date: (srv['date'] ?? loc['date'] ?? '').toString(),
          customer: (srv['supplier_name'] ?? loc['supplier_name'] ?? 'Supplier').toString(),
          agent: 'Purchase Return',
          localData: loc,
          serverData: srv,
          itemRows: itemRows,
          fields: fields,
        );

        if (!showOnlyDiscrepancies || rec.hasDiscrepancy) {
          results.add(rec);
        }
      }
    }

    return results;
  }

  // --- Audit Product Master ---
  Future<List<DiscrepancyRecord>> _auditProductMaster({
    int limit = 500,
    bool showOnlyDiscrepancies = true,
  }) async {
    final db = await DbHelper.instance.database;
    final localRows = await db.rawQuery(
      'SELECT * FROM product_master ORDER BY rowid DESC LIMIT ?',
      [limit],
    );

    final serverRows = await _fetchServerRecords('product_master', limit: limit);

    final localMap = <String, Map<String, dynamic>>{};
    for (var r in localRows) {
      final key = (r['product_name'] ?? r['id'] ?? '').toString().trim().toUpperCase();
      if (key.isNotEmpty) localMap[key] = Map<String, dynamic>.from(r);
    }

    final serverMap = <String, Map<String, dynamic>>{};
    for (var r in serverRows) {
      final key = (r['product_name'] ?? r['id'] ?? '').toString().trim().toUpperCase();
      if (key.isNotEmpty) serverMap[key] = r;
    }

    final allKeys = {...localMap.keys, ...serverMap.keys};
    final results = <DiscrepancyRecord>[];

    for (var k in allKeys) {
      final loc = localMap[k];
      final srv = serverMap[k];

      if (loc == null && srv != null) {
        results.add(DiscrepancyRecord(
          category: 'product_master',
          primaryKey: k,
          title: srv['product_name'] ?? k,
          date: '-',
          customer: 'HSN: ${srv['hsn_code'] ?? '-'}',
          agent: 'Product',
          localData: {},
          serverData: srv,
          fields: [
            DiscrepancyField(fieldName: 'product_name', fieldLabel: 'Product Name', localValue: 'MISSING LOCALLY', serverValue: srv['product_name']),
          ],
          isMissingLocally: true,
        ));
      } else if (loc != null && srv == null) {
        results.add(DiscrepancyRecord(
          category: 'product_master',
          primaryKey: k,
          title: loc['product_name'] ?? k,
          date: '-',
          customer: 'HSN: ${loc['hsn_code'] ?? '-'}',
          agent: 'Product',
          localData: loc,
          serverData: {},
          fields: [
            DiscrepancyField(fieldName: 'product_name', fieldLabel: 'Product Name', localValue: loc['product_name'], serverValue: 'NOT ON SERVER'),
          ],
          isMissingOnServer: true,
        ));
      } else if (loc != null && srv != null) {
        final fields = [
          DiscrepancyField(fieldName: 'product_name', fieldLabel: 'Product Name', localValue: loc['product_name'], serverValue: srv['product_name']),
          DiscrepancyField(fieldName: 'hsn_code', fieldLabel: 'HSN Code', localValue: loc['hsn_code'], serverValue: srv['hsn_code']),
          DiscrepancyField(fieldName: 'gst_percent', fieldLabel: 'GST %', localValue: loc['gst_percent'], serverValue: srv['gst_percent']),
          DiscrepancyField(fieldName: 'mrp', fieldLabel: 'MRP', localValue: loc['mrp'], serverValue: srv['mrp']),
          DiscrepancyField(fieldName: 'stock_qty', fieldLabel: 'Total Stock', localValue: loc['stock_qty'], serverValue: srv['stock_qty']),
        ];

        final rec = DiscrepancyRecord(
          category: 'product_master',
          primaryKey: k,
          title: srv['product_name'] ?? loc['product_name'] ?? k,
          date: '-',
          customer: 'HSN: ${srv['hsn_code'] ?? loc['hsn_code'] ?? '-'}',
          agent: 'Product',
          localData: loc,
          serverData: srv,
          fields: fields,
        );

        if (!showOnlyDiscrepancies || rec.hasDiscrepancy) {
          results.add(rec);
        }
      }
    }

    return results;
  }

  Future<List<DiscrepancyRecord>> _auditGenericTable(
    String table, {
    int limit = 500,
    bool showOnlyDiscrepancies = true,
  }) async {
    return [];
  }

  Future<bool> _postServerRecords(String endpoint, List<Map<String, dynamic>> payloads) async {
    try {
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final uri = Uri.parse('$cleanUrl/rest/v1/$endpoint');
      final headers = {
        'apikey': config.supabaseAnonKey.trim(),
        'Authorization': 'Bearer ${config.supabaseAnonKey.trim()}',
        'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates, return=minimal',
      };
      final res = await http.post(uri, headers: headers, body: jsonEncode(payloads)).timeout(const Duration(seconds: 15));
      return res.statusCode < 400;
    } catch (e) {
      debugPrint('Error posting server records to $endpoint: $e');
      return false;
    }
  }

  /// Reconciles a single discrepancy record bi-directionally between Local PC and Supabase Cloud.
  /// Merges missing line items, repairs non-zero financial totals, and updates both databases to 100% sync.
  Future<bool> reconcileRecordBiDirectionally(DiscrepancyRecord record) async {
    try {
      final db = await DbHelper.instance.database;
      final config = ServerConfigService.instance;
      final cat = record.category;
      final pk = record.primaryKey;
      SupabaseRealtimeService.instance.markKeyRecentlyPushed(pk);

      if (cat == 'purchase_entries' || cat == 'sales_invoices' || cat == 'sales_return_invoices' || cat == 'purchase_return_entries') {
        String itemsTable;
        String fkCol;
        if (cat == 'purchase_entries') {
          itemsTable = 'purchase_items';
          fkCol = 'entry_no';
        } else if (cat == 'sales_invoices') {
          itemsTable = 'sales_items';
          fkCol = 'invoice_no';
        } else if (cat == 'sales_return_invoices') {
          itemsTable = 'sales_return_items';
          fkCol = 'return_no';
        } else {
          itemsTable = 'purchase_return_items';
          fkCol = 'entry_no';
        }

        // 1. Fetch current local items and server items
        final localItems = await db.rawQuery('SELECT * FROM $itemsTable WHERE $fkCol = ? OR $fkCol LIKE ?', [pk, '%_$pk']);
        var serverItems = await _fetchServerRecords('$itemsTable?$fkCol=eq.${Uri.encodeComponent(pk)}');
        if (serverItems.isEmpty) {
          serverItems = await _fetchServerRecords('$itemsTable?$fkCol=ilike.*${Uri.encodeComponent(pk)}');
        }

        // 2. Build line item maps
        final localItemMap = <String, Map<String, dynamic>>{};
        for (var r in localItems) {
          final pName = (r['product_name'] ?? r['name'] ?? '').toString().trim().toUpperCase();
          final bNo = (r['batch_number'] ?? r['batch'] ?? '').toString().trim().toUpperCase();
          localItemMap['${pName}_$bNo'] = Map<String, dynamic>.from(r);
        }

        final serverItemMap = <String, Map<String, dynamic>>{};
        for (var r in serverItems) {
          final pName = (r['product_name'] ?? r['name'] ?? '').toString().trim().toUpperCase();
          final bNo = (r['batch_number'] ?? r['batch'] ?? '').toString().trim().toUpperCase();
          serverItemMap['${pName}_$bNo'] = Map<String, dynamic>.from(r);
        }

        // 3. Merge server items missing on local PC
        num calculatedLocalSubtotal = 0;
        for (var entry in serverItemMap.entries) {
          final k = entry.key;
          final srvItem = entry.value;
          final locItem = localItemMap[k];

          final qSrv = _parseNum(srvItem['quantity'] ?? srvItem['qty']);
          final rateSrv = _parseNum(srvItem['unit_price'] ?? srvItem['p_rate'] ?? srvItem['s_rate'] ?? srvItem['sale_rate'] ?? srvItem['purchase_rate']);
          final discSrv = _parseNum(srvItem['disc_percent']);
          var totSrv = _parseNum(srvItem['total_amount'] ?? srvItem['total'] ?? srvItem['net']);
          if (totSrv == 0 && qSrv > 0 && rateSrv > 0) {
            totSrv = qSrv * rateSrv;
            if (discSrv > 0) totSrv -= (totSrv * discSrv / 100);
          }
          calculatedLocalSubtotal += totSrv;

          if (locItem == null || _parseNum(locItem['quantity'] ?? locItem['qty']) == 0) {
            // Insert or update missing line item locally
            final Map<String, dynamic> cleanInsert = Map<String, dynamic>.from(srvItem);
            cleanInsert[fkCol] = pk;
            cleanInsert.remove('id');
            cleanInsert.remove('created_at');
            cleanInsert.remove('updated_at');

            // Format correct columns for local table
            if (itemsTable == 'purchase_items') {
              cleanInsert['batch'] = srvItem['batch_number'] ?? srvItem['batch'] ?? '';
              cleanInsert['expiry'] = srvItem['expiry_date'] ?? srvItem['expiry'] ?? '';
              cleanInsert['qty'] = qSrv;
              cleanInsert['p_rate'] = rateSrv;
              cleanInsert['total'] = totSrv;
            } else if (itemsTable == 'sales_items') {
              cleanInsert['batch_number'] = srvItem['batch_number'] ?? srvItem['batch'] ?? '';
              cleanInsert['expiry_date'] = srvItem['expiry_date'] ?? srvItem['expiry'] ?? '';
              cleanInsert['qty'] = qSrv;
              cleanInsert['quantity'] = qSrv;
              cleanInsert['s_rate'] = rateSrv;
              cleanInsert['sale_rate'] = rateSrv;
              cleanInsert['total'] = totSrv;
            }

            try {
              await db.insert(itemsTable, cleanInsert, conflictAlgorithm: sql.ConflictAlgorithm.replace);
            } catch (e) {
              debugPrint('Reconcile insert item error: $e');
            }
          }
        }

        // 4. Merge local items missing on server
        for (var entry in localItemMap.entries) {
          final k = entry.key;
          final locItem = entry.value;
          final srvItem = serverItemMap[k];

          final qLoc = _parseNum(locItem['quantity'] ?? locItem['qty']);
          final rateLoc = _parseNum(locItem['s_rate'] ?? locItem['sale_rate'] ?? locItem['unit_price'] ?? locItem['p_rate']);
          final discLoc = _parseNum(locItem['disc_percent']);
          var totLoc = _parseNum(locItem['total_amount'] ?? locItem['total'] ?? locItem['net']);
          if (totLoc == 0 && qLoc > 0 && rateLoc > 0) {
            totLoc = qLoc * rateLoc;
            if (discLoc > 0) totLoc -= (totLoc * discLoc / 100);
          }
          if (srvItem == null && qLoc > 0) {
            // Push missing line item to Supabase REST
            final cleanPayload = Map<String, dynamic>.from(locItem);
            cleanPayload[fkCol] = pk;
            cleanPayload['branch_id'] = config.storeBranchId;
            cleanPayload['terminal_id'] = config.terminalId;
            SupabaseRealtimeService.instance.markKeyRecentlyPushed(pk);
            await _postServerRecords(itemsTable, [cleanPayload]);
          }
        }

        // 5. Reconcile Header Totals (Sub Total & Grand Total)
        final locHeader = record.localData;
        final srvHeader = record.serverData;

        num localNet = _parseNum(locHeader['inv_total'] ?? locHeader['grand_total'] ?? locHeader['net_amount'] ?? locHeader['total_amount']);
        num serverNet = _parseNum(srvHeader['net_amount'] ?? srvHeader['inv_total'] ?? srvHeader['grand_total'] ?? srvHeader['total_amount']);

        num localSub = _parseNum(locHeader['sub_total'] ?? locHeader['subtotal']);
        num serverSub = _parseNum(srvHeader['subtotal'] ?? srvHeader['sub_total']);

        // If local has 0 subtotal, recalculate from line items or server
        if (localSub == 0 && calculatedLocalSubtotal > 0) {
          localSub = calculatedLocalSubtotal;
        }
        if (localNet == 0 && localSub > 0) {
          final disc = _parseNum(locHeader['discount'] ?? locHeader['discount_amount']);
          final round = _parseNum(locHeader['round_off']);
          localNet = localSub - disc + round;
        }

        // Update local header SQLite record if local had 0 or missing values
        if (locHeader.isNotEmpty) {
          final updateMap = <String, dynamic>{};
          if (cat == 'purchase_entries') {
            updateMap['sub_total'] = localSub;
            updateMap['inv_total'] = localNet;
            updateMap['grand_total'] = localNet;
            updateMap['is_synced'] = 1;
            await db.update('purchase_entries', updateMap, where: 'entry_no = ? OR entry_no LIKE ?', whereArgs: [pk, '%_$pk']);
          } else if (cat == 'sales_invoices') {
            updateMap['sub_total'] = localSub;
            updateMap['total_amount'] = localNet;
            updateMap['grand_total'] = localNet;
            updateMap['is_synced'] = 1;
            await db.update('sales_invoices', updateMap, where: 'entry_no = ? OR invoice_no = ? OR entry_no LIKE ? OR invoice_no LIKE ?', whereArgs: [pk, pk, '%_$pk', '%_$pk']);
          }
        } else {
          // If completely missing locally, insert full header
          final Map<String, dynamic> cleanHeader = Map<String, dynamic>.from(srvHeader);
          cleanHeader['is_synced'] = 1;
          await db.insert(cat, cleanHeader, conflictAlgorithm: sql.ConflictAlgorithm.replace);
        }

        // Update server header REST record if server had 0 or missing values
        final bestSub = (serverSub > 0) ? serverSub : localSub;
        final bestNet = (serverNet > 0) ? serverNet : localNet;

        final serverPayload = <String, dynamic>{
          'entry_no': pk,
          'invoice_no': pk,
          'subtotal': bestSub,
          'sub_total': bestSub,
          'net_amount': bestNet,
          'inv_total': bestNet,
          'grand_total': bestNet,
          'total_amount': bestNet,
          'supplier_name': srvHeader['supplier_name'] ?? locHeader['supplier_name'] ?? '',
          'customer_name': srvHeader['customer_name'] ?? locHeader['customer_name'] ?? '',
          'date': srvHeader['date'] ?? locHeader['date'] ?? '',
          'branch_id': config.storeBranchId,
          'terminal_id': config.terminalId,
          'updated_at': DateTime.now().toIso8601String(),
        };

        SupabaseRealtimeService.instance.markKeyRecentlyPushed(pk);
        await _postServerRecords('$cat?on_conflict=entry_no', [serverPayload]);

        return true;
      } else if (cat == 'product_master' || cat == 'stock_batches') {
        // Master Data 2-Way Reconciliation by timestamp or presence
        final loc = record.localData;
        final srv = record.serverData;

        if (loc.isEmpty && srv.isNotEmpty) {
          final cleanInsert = Map<String, dynamic>.from(srv);
          cleanInsert['is_synced'] = 1;
          cleanInsert.remove('created_at');
          await db.insert(cat, cleanInsert, conflictAlgorithm: sql.ConflictAlgorithm.replace);
        } else if (loc.isNotEmpty && srv.isEmpty) {
          final cleanPayload = Map<String, dynamic>.from(loc);
          cleanPayload['branch_id'] = config.storeBranchId;
          cleanPayload['terminal_id'] = config.terminalId;
          SupabaseRealtimeService.instance.markKeyRecentlyPushed(pk);
          await _postServerRecords(cat, [cleanPayload]);
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error in reconcileRecordBiDirectionally: $e');
      return false;
    }
  }

  /// Reconciles all detected discrepancies in a category bi-directionally
  Future<int> reconcileCategoryBiDirectionally(String categoryKey) async {
    int successCount = 0;
    try {
      final records = await fetchDiscrepancies(categoryKey: categoryKey, limit: 500, showOnlyDiscrepancies: true);
      for (var rec in records) {
        if (rec.hasDiscrepancy) {
          final ok = await reconcileRecordBiDirectionally(rec);
          if (ok) successCount++;
        }
      }
    } catch (e) {
      debugPrint('Error reconciling category $categoryKey: $e');
    }
    return successCount;
  }
}
