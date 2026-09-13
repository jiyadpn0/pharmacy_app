import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../providers/pharmacy_provider.dart';

class ProductRepository {
  /// Fetches paginated product master items with optional search query.
  static Future<List<Product>> getPagedProducts({
    required int limit,
    required int offset,
    String searchQuery = '',
    PharmacyProvider? pharmacyProvider,
  }) async {
    if (kIsWeb) {
      if (pharmacyProvider == null) return [];
      var list = pharmacyProvider.productMaster;
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        list = list.where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.genericName.toLowerCase().contains(q) ||
            p.hsnCode.toLowerCase().contains(q) ||
            p.category.toLowerCase().contains(q) ||
            p.rack.toLowerCase().contains(q)).toList();
      }
      if (offset >= list.length) return [];
      return list.skip(offset).take(limit).toList();
    }

    try {
      final db = await DbHelper.instance.database;
      String sql = '''
        SELECT pm.*,
          IFNULL((SELECT SUM(sb.current_stock) FROM stock_batches sb WHERE sb.product_id = pm.id), 0) AS total_stock
        FROM product_master pm
      ''';
      List<dynamic> args = [];

      if (searchQuery.trim().isNotEmpty) {
        final q = '%${searchQuery.trim().toLowerCase()}%';
        sql += '''
          WHERE (LOWER(pm.name) LIKE ? 
             OR LOWER(pm.generic_name) LIKE ? 
             OR LOWER(pm.hsn_code) LIKE ? 
             OR LOWER(pm.category_id) LIKE ? 
             OR LOWER(pm.rack_id) LIKE ?)
        ''';
        args.addAll([q, q, q, q, q]);
      }

      sql += ' ORDER BY pm.name ASC LIMIT ? OFFSET ?';
      args.add(limit);
      args.add(offset);

      final results = await db.rawQuery(sql, args);

      if (results.isEmpty && pharmacyProvider != null && pharmacyProvider.productMaster.isNotEmpty && offset == 0) {
        var list = pharmacyProvider.productMaster;
        if (searchQuery.isNotEmpty) {
          final q = searchQuery.toLowerCase().trim();
          list = list.where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.genericName.toLowerCase().contains(q) ||
              p.hsnCode.toLowerCase().contains(q) ||
              p.category.toLowerCase().contains(q) ||
              p.rack.toLowerCase().contains(q)).toList();
        }
        if (offset >= list.length) return [];
        return list.skip(offset).take(limit).toList();
      }

      return results.map((row) {
        String pId = row['id']?.toString() ?? '';
        String pName = row['name']?.toString() ?? '';
        String gen = row['generic_name']?.toString() ?? '';

        if (gen.trim().isEmpty && pharmacyProvider != null) {
          gen = pharmacyProvider.resolveGenericName(pName, productId: pId);
          if (gen.isNotEmpty) {
            db.rawUpdate("UPDATE product_master SET generic_name = ? WHERE id = ?", [gen, pId]);
          }
        }

        return Product(
          id: pId,
          name: pName,
          genericName: gen,
          manufacturer: row['manufacturer_id']?.toString() ?? '',
          category: row['category_id']?.toString() ?? '',
          subCategory: row['sub_category_id']?.toString() ?? '',
          rack: row['rack_id']?.toString() ?? '',
          hsnCode: row['hsn_code']?.toString() ?? '',
          gstPercent: (row['gst_percent'] as num?)?.toDouble() ?? 12.0,
          sDiscPercent: (row['s_disc_percent'] as num?)?.toDouble() ?? 0.0,
          schedule: row['schedule']?.toString() ?? 'H',
          reorderLevel: (row['reorder_level'] as num?)?.toInt() ?? 10,
          maxLevel: (row['max_level'] as num?)?.toInt() ?? 100,
          packSize: (row['packing'] as num?)?.toInt() ?? 1,
          mrp: (row['mrp'] as num?)?.toDouble() ?? 0.0,
          purchaseRate: (row['purchase_rate'] as num?)?.toDouble() ?? 0.0,
          salePrice: (row['sale_rate'] as num?)?.toDouble() ?? 0.0,
          patent: row['patent']?.toString() ?? '',
          isControlled: row['is_controlled'] == 1,
          isBanned: row['is_banned'] == 1,
          isNrx: row['is_nrx'] == 1,
          isActive: row['is_active'] == 1,
          isDiscLocked: row['is_disc_locked'] == 1,
          preferredWholesale: row['preferred_wholesale']?.toString() ?? '',
          leadTime: (row['lead_time'] as num?)?.toInt() ?? 2,
          stock: (row['total_stock'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } catch (e) {
      debugPrint("Error fetching paged products: $e");
      if (pharmacyProvider != null) {
        var list = pharmacyProvider.productMaster;
        if (searchQuery.isNotEmpty) {
          final q = searchQuery.toLowerCase().trim();
          list = list.where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.genericName.toLowerCase().contains(q) ||
              p.hsnCode.toLowerCase().contains(q) ||
              p.category.toLowerCase().contains(q) ||
              p.rack.toLowerCase().contains(q)).toList();
        }
        if (offset >= list.length) return [];
        return list.skip(offset).take(limit).toList();
      }
      return [];
    }
  }

  /// Fetches paginated live stock batches with filter mode and search query.
  static Future<List<Product>> getPagedStockBatches({
    required int limit,
    required int offset,
    String searchQuery = '',
    String filterMode = 'Available', // "All", "Available", "Out of Stock", "Low Stock", "Expired"
    PharmacyProvider? pharmacyProvider,
  }) async {
    if (kIsWeb) {
      if (pharmacyProvider == null) return [];
      var list = _filterStockInMemory(pharmacyProvider.products, pharmacyProvider.productMaster, searchQuery, filterMode);
      if (offset >= list.length) return [];
      return list.skip(offset).take(limit).toList();
    }

    try {
      final db = await DbHelper.instance.database;
      String sql = '''
        SELECT 
          sb.product_id,
          sb.batch_number,
          sb.expiry_date,
          sb.mfg_date,
          sb.current_stock,
          sb.purchase_rate,
          sb.landing_cost,
          sb.mrp,
          sb.sale_rate,
          sb.s_disc_percent,
          sb.gst_percent,
          sb.rack AS batch_rack,
          sb.supplier_name,
          sb.packing AS batch_packing,
          pm.name AS product_name,
          pm.generic_name,
          pm.hsn_code,
          pm.category_id,
          pm.sub_category_id,
          pm.rack_id AS master_rack,
          pm.reorder_level,
          pm.max_level,
          pm.patent,
          pm.schedule
        FROM stock_batches sb
        LEFT JOIN product_master pm ON sb.product_id = pm.id
      ''';

      List<String> conditions = [];
      List<dynamic> args = [];

      if (filterMode == 'Available') {
        conditions.add('sb.current_stock > 0');
      } else if (filterMode == 'Out of Stock') {
        conditions.add('sb.current_stock <= 0');
      } else if (filterMode == 'Low Stock') {
        conditions.add('sb.current_stock > 0 AND sb.current_stock <= IFNULL(pm.reorder_level, 10)');
      } else if (filterMode == 'Negative Stock') {
        conditions.add('sb.current_stock < 0');
      }

      if (searchQuery.trim().isNotEmpty) {
        final q = '%${searchQuery.trim().toLowerCase()}%';
        conditions.add('''
          (LOWER(pm.name) LIKE ? 
           OR LOWER(sb.batch_number) LIKE ? 
           OR LOWER(pm.generic_name) LIKE ? 
           OR LOWER(sb.rack) LIKE ? 
           OR LOWER(pm.rack_id) LIKE ?)
        ''');
        args.addAll([q, q, q, q, q]);
      }

      if (conditions.isNotEmpty) {
        sql += ' WHERE ${conditions.join(' AND ')}';
      }

      sql += ' ORDER BY pm.name ASC, sb.expiry_date ASC LIMIT ? OFFSET ?';
      args.add(limit);
      args.add(offset);

      final results = await db.rawQuery(sql, args);

      if (results.isEmpty && pharmacyProvider != null && pharmacyProvider.products.isNotEmpty && offset == 0) {
        var list = _filterStockInMemory(pharmacyProvider.products, pharmacyProvider.productMaster, searchQuery, filterMode);
        if (offset >= list.length) return [];
        return list.skip(offset).take(limit).toList();
      }

      final parsedList = results.map((row) {
        final stock = (row['current_stock'] as num?)?.toInt() ?? 0;
        final reorder = (row['reorder_level'] as num?)?.toInt() ?? 10;
        final expiryStr = row['expiry_date']?.toString() ?? '';
        final batchRack = row['batch_rack']?.toString() ?? '';
        final masterRack = row['master_rack']?.toString() ?? '';

        String pId = row['product_id']?.toString() ?? '';
        String pName = row['product_name']?.toString() ?? 'UNKNOWN';
        String gen = row['generic_name']?.toString() ?? '';

        if (gen.trim().isEmpty && pharmacyProvider != null) {
          gen = pharmacyProvider.resolveGenericName(pName, productId: pId);
        }

        return Product(
          id: pId,
          name: pName,
          genericName: gen,
          hsnCode: row['hsn_code']?.toString() ?? '',
          category: row['category_id']?.toString() ?? '',
          subCategory: row['sub_category_id']?.toString() ?? '',
          batch: row['batch_number']?.toString() ?? '',
          expiry: expiryStr,
          stock: stock,
          purchaseRate: (row['purchase_rate'] as num?)?.toDouble() ?? 0.0,
          landingCost: (row['landing_cost'] as num?)?.toDouble() ?? 0.0,
          mrp: (row['mrp'] as num?)?.toDouble() ?? 0.0,
          salePrice: (row['sale_rate'] as num?)?.toDouble() ?? 0.0,
          gstPercent: (row['gst_percent'] as num?)?.toDouble() ?? 12.0,
          sDiscPercent: (row['s_disc_percent'] as num?)?.toDouble() ?? 0.0,
          supplier: row['supplier_name']?.toString() ?? '',
          rack: batchRack.isNotEmpty ? batchRack : masterRack,
          packSize: (row['batch_packing'] as num?)?.toInt() ?? 1,
          reorderLevel: reorder,
          maxLevel: (row['max_level'] as num?)?.toInt() ?? 100,
          patent: row['patent']?.toString() ?? '',
          schedule: row['schedule']?.toString() ?? 'H',
        );
      }).toList();

      if (filterMode == 'Expired') {
        final now = DateTime.now();
        return parsedList.where((p) => p.stock > 0 && _parseExpiry(p.expiry).isBefore(now)).toList();
      }

      return parsedList;
    } catch (e) {
      debugPrint("Error fetching paged stock batches: $e");
      if (pharmacyProvider != null) {
        var list = _filterStockInMemory(pharmacyProvider.products, pharmacyProvider.productMaster, searchQuery, filterMode);
        if (offset >= list.length) return [];
        return list.skip(offset).take(limit).toList();
      }
      return [];
    }
  }

  static DateTime _parseExpiry(String exp) {
    if (!exp.contains('/')) return DateTime(2099);
    final parts = exp.split('/');
    int m = int.tryParse(parts[0]) ?? 1;
    int y = int.tryParse(parts[1]) ?? 99;
    if (y < 100) y += 2000;
    return DateTime(y, m + 1, 0);
  }

  static List<Product> _filterStockInMemory(
    List<Product> products,
    List<Product> productMaster,
    String query,
    String filterMode,
  ) {
    final now = DateTime.now();
    final cleanQ = Product.cleanProductName(query).toLowerCase();
    final Map<String, int> reorderLevels = {
      for (var master in productMaster) Product.cleanProductName(master.name): master.reorderLevel
    };

    final filtered = products.where((item) {
      final cleanName = Product.cleanProductName(item.name).toLowerCase();
      final cleanBatch = item.batch.toLowerCase().trim();
      final cleanGeneric = Product.cleanProductName(item.genericName).toLowerCase();
      final cleanRack = item.rack.toLowerCase().trim();

      bool matchesSearch = cleanQ.isEmpty ||
          cleanName.contains(cleanQ) ||
          cleanBatch.contains(cleanQ) ||
          cleanGeneric.contains(cleanQ) ||
          cleanRack.contains(cleanQ);
      if (!matchesSearch) return false;

      if (filterMode == "Available") {
        return item.stock > 0;
      } else if (filterMode == "Out of Stock") {
        return item.stock <= 0;
      } else if (filterMode == "Expired") {
        return item.stock > 0 && _parseExpiry(item.expiry).isBefore(now);
      } else if (filterMode == "Low Stock") {
        int reorderLevel = reorderLevels[Product.cleanProductName(item.name)] ?? 10;
        return item.stock > 0 && item.stock <= reorderLevel;
      } else if (filterMode == "Negative Stock") {
        return item.stock < 0;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      int nameCompare = a.name.compareTo(b.name);
      if (nameCompare != 0) return nameCompare;
      return _parseExpiry(a.expiry).compareTo(_parseExpiry(b.expiry));
    });

    return filtered;
  }
}
