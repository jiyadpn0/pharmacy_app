import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../models/erp_models.dart';
import '../models/buy_planning_models.dart';
import '../services/stock_outbox_service.dart';

/// Professional Buy Planning & Purchase Order Management Service
class BuyPlanningService {
  BuyPlanningService._();
  static final BuyPlanningService instance = BuyPlanningService._();

  /// Fast load: product master with current aggregated stock and ranking levels
  Future<List<BuyPlanItem>> getBasePlanItems({
    ReorderAlgorithm algorithm = ReorderAlgorithm.dynamicHybrid,
  }) async {
    try {
      final db = await DbHelper.instance.database;
      const String query = '''
        SELECT 
          p.id,
          p.name,
          p.rack_id as rack,
          IFNULL(p.category_id, 'General') as classification,
          IFNULL(p.generic_name, '') as content,
          IFNULL(p.mrp, 0.0) as mrp,
          IFNULL(p.purchase_rate, 0.0) as pRate,
          IFNULL(p.manufacturer_id, IFNULL(p.patent, '')) as brand,
          p.packing as packSize,
          p.reorder_level as minLevel,
          p.max_level as maxLevel,
          IFNULL(p.preferred_wholesale, '-') as preferred_wholesale,
          IFNULL(s.total_stock, 0.0) as currentBalance,
          0.0 as intervalSaleQty,
          '-' as lastSaleEntryNo,
          0.0 as lastSaleQty,
          0 as lastOrderType,
          '' as lastSaleDate,
          0.0 as maxSingleTxn4M,
          '' as firstPurchaseDate,
          '' as mappedName,
          IFNULL(p.preferred_wholesale, '-') as bestProfitWholesale,
          '-' as latestOffer,
          0.0 as rank
        FROM product_master p
        LEFT JOIN (
          SELECT product_id, SUM(current_stock) as total_stock
          FROM stock_batches
          GROUP BY product_id
        ) s ON p.id = s.product_id
        WHERE p.is_active = 1 OR s.total_stock > 0
        ORDER BY p.name ASC
      ''';

      final List<Map<String, dynamic>> rows = await db.rawQuery(query);
      return rows.map((r) => BuyPlanningEngine.calculate(raw: r, algorithm: algorithm)).toList();
    } catch (e, stack) {
      debugPrint("Error in BuyPlanningService.getBasePlanItems: $e\n$stack");
      return [];
    }
  }

  /// Advanced load: full historical velocity, maximum single sale spikes, mapped names, and ranking
  Future<List<BuyPlanItem>> getAdvancedPlanItems({
    DateTime? fromDate,
    DateTime? toDate,
    ReorderAlgorithm algorithm = ReorderAlgorithm.dynamicHybrid,
  }) async {
    try {
      final db = await DbHelper.instance.database;
      final now = DateTime.now();
      final d4mDate = now.subtract(const Duration(days: 120));
      final d4mDay = DateFormat('yyyy-MM-dd').format(d4mDate);

      // Base active products
      const String baseQuery = '''
        SELECT 
          p.id,
          p.name,
          p.rack_id as rack,
          IFNULL(p.category_id, 'General') as classification,
          IFNULL(p.generic_name, '') as content,
          IFNULL(p.mrp, 0.0) as mrp,
          IFNULL(p.purchase_rate, 0.0) as pRate,
          IFNULL(p.manufacturer_id, IFNULL(p.patent, '')) as brand,
          p.packing as packSize,
          p.reorder_level as minLevel,
          p.max_level as maxLevel,
          IFNULL(p.preferred_wholesale, '-') as preferred_wholesale,
          IFNULL(s.total_stock, 0.0) as currentBalance
        FROM product_master p
        LEFT JOIN (
          SELECT product_id, SUM(current_stock) as total_stock
          FROM stock_batches
          GROUP BY product_id
        ) s ON p.id = s.product_id
        WHERE p.is_active = 1 OR s.total_stock > 0
        ORDER BY p.name ASC
      ''';

      // Most recent sale per product
      const String lastSalesQuery = '''
        WITH RankedLastSales AS (
          SELECT 
            si.product_id,
            si.qty as last_qty,
            sn.entry_no as last_entry,
            IFNULL(sn.order_type, 0) as last_order_type,
            sn.date as last_date,
            ROW_NUMBER() OVER (
              PARTITION BY si.product_id 
              ORDER BY (CASE WHEN sn.date LIKE '%/%' THEN substr(sn.date, 7, 4) || '-' || substr(sn.date, 4, 2) || '-' || substr(sn.date, 1, 2) ELSE substr(sn.date, 1, 10) END) DESC,
                       CAST(sn.entry_no AS INTEGER) DESC
            ) as rn
          FROM sales_items si
          JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
          WHERE (sn.is_deleted = 0 OR sn.is_deleted IS NULL)
            AND si.product_id IS NOT NULL AND si.product_id != ''
        )
        SELECT product_id, last_qty, last_entry, last_order_type, last_date
        FROM RankedLastSales
        WHERE rn = 1
      ''';

      // 4-month maximum single transaction
      final String maxTxnQuery = '''
        SELECT product_id, MAX(qty) as max_qty
        FROM sales_items si
        JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
        WHERE (sn.is_deleted = 0 OR sn.is_deleted IS NULL)
          AND (CASE WHEN sn.date LIKE '%/%' THEN substr(sn.date, 7, 4) || '-' || substr(sn.date, 4, 2) || '-' || substr(sn.date, 1, 2) ELSE substr(sn.date, 1, 10) END) >= '$d4mDay'
        GROUP BY product_id
      ''';

      // First purchase date per product
      const String firstPurQuery = '''
        SELECT product_id, MIN(date) as first_pur_date
        FROM purchase_invoices
        WHERE date IS NOT NULL AND date != ''
        GROUP BY product_id
      ''';

      // Product mappings (wholesaler external naming)
      const String mappingsQuery = '''
        SELECT 
          target_product_id, 
          GROUP_CONCAT(external_item_name, ', ') as mapped_names,
          wholesaler_name
        FROM product_mappings
        GROUP BY target_product_id
      ''';

      // Sales velocity in interval
      String intervalQuery;
      List<dynamic> intervalArgs = [];
      if (fromDate != null && toDate != null) {
        final fStr = DateFormat('yyyy-MM-dd').format(fromDate);
        final tStr = DateFormat('yyyy-MM-dd').format(toDate);
        intervalQuery = '''
          SELECT product_id, SUM(qty) as interval_qty
          FROM sales_items si
          JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
          WHERE (sn.is_deleted = 0 OR sn.is_deleted IS NULL)
            AND (CASE WHEN sn.date LIKE '%/%' THEN substr(sn.date, 7, 4) || '-' || substr(sn.date, 4, 2) || '-' || substr(sn.date, 1, 2) ELSE substr(sn.date, 1, 10) END) >= ?
            AND (CASE WHEN sn.date LIKE '%/%' THEN substr(sn.date, 7, 4) || '-' || substr(sn.date, 4, 2) || '-' || substr(sn.date, 1, 2) ELSE substr(sn.date, 1, 10) END) <= ?
          GROUP BY product_id
        ''';
        intervalArgs = [fStr, tStr];
      } else {
        final d30Day = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 30)));
        intervalQuery = '''
          SELECT product_id, SUM(qty) as interval_qty
          FROM sales_items si
          JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
          WHERE (sn.is_deleted = 0 OR sn.is_deleted IS NULL)
            AND (CASE WHEN sn.date LIKE '%/%' THEN substr(sn.date, 7, 4) || '-' || substr(sn.date, 4, 2) || '-' || substr(sn.date, 1, 2) ELSE substr(sn.date, 1, 10) END) >= '$d30Day'
          GROUP BY product_id
        ''';
      }

      // Execute queries in parallel
      final results = await Future.wait([
        db.rawQuery(baseQuery),
        db.rawQuery(lastSalesQuery),
        db.rawQuery(maxTxnQuery),
        db.rawQuery(firstPurQuery),
        db.rawQuery(mappingsQuery),
        db.rawQuery(intervalQuery, intervalArgs),
      ]);

      final rawProducts = results[0];
      final lastSales = results[1];
      final maxTxns = results[2];
      final firstPurs = results[3];
      final mappings = results[4];
      final intervalSales = results[5];

      final Map<String, Map<String, dynamic>> lastSaleMap = {
        for (var r in lastSales) r['product_id']?.toString() ?? '': r
      };
      final Map<String, double> maxTxnMap = {
        for (var r in maxTxns) r['product_id']?.toString() ?? '': (r['max_qty'] as num?)?.toDouble() ?? 0.0
      };
      final Map<String, String> firstPurMap = {
        for (var r in firstPurs) r['product_id']?.toString() ?? '': r['first_pur_date']?.toString() ?? ''
      };
      final Map<String, Map<String, dynamic>> mappingsMap = {
        for (var r in mappings) r['target_product_id']?.toString() ?? '': r
      };
      final Map<String, double> intervalMap = {
        for (var r in intervalSales) r['product_id']?.toString() ?? '': (r['interval_qty'] as num?)?.toDouble() ?? 0.0
      };

      final List<BuyPlanItem> planItems = [];

      for (var prod in rawProducts) {
        final String pid = prod['id']?.toString() ?? '';
        final lastSale = lastSaleMap[pid];
        final mapping = mappingsMap[pid];

        final Map<String, dynamic> enriched = Map<String, dynamic>.from(prod);
        enriched['lastSaleEntryNo'] = lastSale?['last_entry']?.toString() ?? '-';
        enriched['lastSaleQty'] = (lastSale?['last_qty'] as num?)?.toDouble() ?? 0.0;
        enriched['lastOrderType'] = (lastSale?['last_order_type'] as num?)?.toInt() ?? 0;
        enriched['lastSaleDate'] = lastSale?['last_date']?.toString() ?? '';
        enriched['maxSingleTxn4M'] = maxTxnMap[pid] ?? 0.0;
        enriched['firstPurchaseDate'] = firstPurMap[pid] ?? '';
        enriched['mappedName'] = mapping?['mapped_names']?.toString() ?? '';
        enriched['bestProfitWholesale'] = mapping?['wholesaler_name']?.toString() ?? prod['preferred_wholesale'] ?? '-';
        enriched['intervalSaleQty'] = intervalMap[pid] ?? 0.0;
        enriched['sales_30d'] = intervalMap[pid] ?? 0.0;

        planItems.add(BuyPlanningEngine.calculate(raw: enriched, algorithm: algorithm));
      }

      return planItems;
    } catch (e, stack) {
      debugPrint("Error in BuyPlanningService.getAdvancedPlanItems: $e\n$stack");
      return [];
    }
  }

  /// Transactionally generates Purchase Orders grouped by supplier, saves to SQLite,
  /// and queues outbox mutations for reliable multi-PC cloud sync.
  Future<List<OrderConfirmation>> generatePurchaseOrders({
    required List<Map<String, dynamic>> selectedItems,
    required DateTime orderDate,
    String? customNotes,
  }) async {
    if (selectedItems.isEmpty) return [];

    // Group items by target supplier
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var item in selectedItems) {
      final supplier = (item['supplier'] ?? item['preferred_wholesale'] ?? item['preferredWholesale'] ?? 'General Wholesale').toString().trim();
      final key = supplier.isEmpty || supplier == '-' ? 'General Wholesale' : supplier;
      grouped.putIfAbsent(key, () => []).add(item);
    }

    final List<OrderConfirmation> createdOrders = [];
    final db = await DbHelper.instance.database;

    await db.transaction((txn) async {
      int seqCounter = 0;
      for (var entry in grouped.entries) {
        final supplierName = entry.key;
        final items = entry.value;

        // Structured, human-readable yet unique Order ID
        final datePrefix = DateFormat('yyyyMMdd').format(orderDate);
        final timeSuffix = (DateTime.now().millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0');
        final orderId = "PO-$datePrefix-$timeSuffix-${seqCounter + 1}";

        final List<OrderConfirmationItem> orderItems = items.map((i) {
          final pid = (i['id'] ?? i['productId'] ?? '').toString();
          final name = (i['name'] ?? i['productName'] ?? '').toString();
          final brand = (i['brand'] ?? i['company'] ?? '').toString();
          final int pack = math.max(1, (i['packSize'] as num?)?.toInt() ?? 1);
          final double rate = (i['pRate'] as num?)?.toDouble() ?? (i['purchaseRate'] as num?)?.toDouble() ?? 0.0;
          final int qty = math.max(1, (i['orderQty'] as num?)?.toInt() ?? (i['suggested_packs'] as num?)?.toInt() ?? 1);

          return OrderConfirmationItem(
            orderId: orderId,
            productId: pid,
            productName: name,
            company: brand,
            orderQty: qty,
            packSize: pack,
            unitPrice: rate,
          );
        }).toList();

        final double totalAmt = orderItems.fold(0.0, (sum, it) => sum + (it.orderQty * it.unitPrice));
        final expectedDelivery = DateFormat('dd/MM/yyyy').format(orderDate.add(const Duration(days: 2)));

        final order = OrderConfirmation(
          orderId: orderId,
          orderDate: orderDate,
          supplierName: supplierName,
          totalItems: orderItems.length,
          totalAmount: totalAmt,
          status: 'PENDING',
          expectedDeliveryDate: expectedDelivery,
          notes: customNotes ?? "Generated via Professional Buy Planning on ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}",
          createdAt: DateTime.now(),
          items: orderItems,
        );

        // 1. Insert header
        await txn.insert('purchase_orders', {
          'order_id': order.orderId,
          'order_date': order.orderDate.toIso8601String(),
          'supplier_name': order.supplierName,
          'total_items': order.totalItems,
          'total_amount': order.totalAmount,
          'status': order.status,
          'expected_delivery_date': order.expectedDeliveryDate,
          'notes': order.notes,
          'created_at': order.createdAt.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        // 2. Insert line items
        for (var it in orderItems) {
          await txn.insert('purchase_order_items', {
            'order_id': it.orderId,
            'product_id': it.productId,
            'product_name': it.productName,
            'company': it.company,
            'order_qty': it.orderQty,
            'pack_size': it.packSize,
            'unit_price': it.unitPrice,
            'received_qty': 0,
            'status': 'PENDING',
          });
        }

        // 3. Queue to outbox for cloud sync (idempotent, background drain)
        try {
          await StockOutboxService.instance.queueOperation(
            operationType: 'PURCHASE_ORDER_CREATE',
            referenceNo: order.orderId,
            executor: txn,
            payload: {
              'order': order.toMap(),
              'items': orderItems.map((e) => {
                'order_id': e.orderId,
                'product_id': e.productId,
                'product_name': e.productName,
                'order_qty': e.orderQty,
                'pack_size': e.packSize,
                'unit_price': e.unitPrice,
              }).toList(),
            },
          );
        } catch (e) {
          debugPrint("Outbox enqueue warning for PO ${order.orderId}: $e");
        }

        createdOrders.add(order);
        seqCounter++;
      }
    });

    return createdOrders;
  }
}
