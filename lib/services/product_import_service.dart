import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import 'supabase_sync_service.dart';
import 'server_config_service.dart';

class ProductImportService {
  static final ProductImportService instance = ProductImportService._init();
  ProductImportService._init();

  /// Default exported CSV path from old database extraction
  static const String defaultCsvPath =
      r'C:\Users\HP\AppData\Local\Google\AndroidStudio2026.2.1\projects\pharmacy_app.2a94c7a9\.artifacts\22ea4bab-6250-47fd-aee5-47653c3634ae\scratch\pharmacy_57k_full_catalog_with_salts.csv';

  /// High-performance bulk import of 57,059 products into SQLite database
  Future<Map<String, dynamic>> import57kCatalog({
    String? filePath,
    void Function(int processed, int total)? onProgress,
  }) async {
    final path = filePath ?? defaultCsvPath;
    final file = File(path);

    if (!await file.exists()) {
      return {
        'success': false,
        'message': 'Exported CSV file not found at path: $path',
        'count': 0,
      };
    }

    final db = await DbHelper.instance.database;

    // Set high-performance PRAGMAs and lock sync during bulk import
    SupabaseSyncService.instance.setBulkImportActive(true);
    await SupabaseSyncService.instance.pauseSyncAndAwaitIdle(
      timeout: const Duration(seconds: 15),
      keepPausedOnTimeout: true,
    );

    try {
      await db.execute('PRAGMA journal_mode = WAL;');
      await db.execute('PRAGMA synchronous = NORMAL;');
      await db.execute('PRAGMA busy_timeout = 30000;');
    } catch (e) {
      debugPrint('PRAGMA setup note: $e');
    }

    // Ensure performance indexes exist
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pm_name ON product_master(name);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pm_generic ON product_master(generic_name);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pm_barcode ON product_master(barcode);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_generic ON products(generic_name);');
    } catch (e) {
      debugPrint('Index creation note: $e');
    }

    int insertedCount = 0;

    try {
      final lines = await file.readAsLines(encoding: utf8);
      if (lines.length <= 1) {
        return {
          'success': false,
          'message': 'CSV file is empty or missing data rows.',
          'count': 0,
        };
      }

      final totalRows = lines.length - 1; // Exclude header
      final DateTime now = DateTime.now();
      final String nowIso = now.toIso8601String();

      // Process in fast batches of 2,000 items per transaction
      const int batchSize = 2000;
      List<List<String>> rowBatch = [];

      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final fields = _parseCsvLine(line);
        if (fields.isNotEmpty) {
          rowBatch.add(fields);
        }

        if (rowBatch.length >= batchSize || i == lines.length - 1) {
          await db.transaction((txn) async {
            final Batch batch = txn.batch();

            for (final fields in rowBatch) {
              if (fields.length < 2) continue;

              final String productId = fields.isNotEmpty ? fields[0].replaceAll('"', '').trim() : '';
              final String rawProductName = fields.length > 1 ? fields[1].replaceAll('"', '').trim() : '';
              final String saltGeneric = fields.length > 2 ? fields[2].replaceAll('"', '').trim() : '';
              final String brandCompany = fields.length > 3 ? fields[3].replaceAll('"', '').trim() : '';
              final String manufacturer = fields.length > 4 ? fields[4].replaceAll('"', '').trim() : '';
              final String category = fields.length > 5 ? fields[5].replaceAll('"', '').trim() : '';
              final String hsnCode = fields.length > 6 ? fields[6].replaceAll('"', '').trim() : '';
              final double gstPercent = fields.length > 7 ? (double.tryParse(fields[7].replaceAll('"', '').trim()) ?? 12.0) : 12.0;
              final int packingRatio = fields.length > 10 ? (int.tryParse(fields[10].replaceAll('"', '').trim()) ?? 10) : 10;
              final String barcode = fields.length > 11 ? fields[11].replaceAll('"', '').trim() : '';
              final int reorderLevel = fields.length > 12 ? (int.tryParse(fields[12].replaceAll('"', '').trim()) ?? 10) : 10;
              final double avgMrp = fields.length > 13 ? (double.tryParse(fields[13].replaceAll('"', '').trim()) ?? 0.0) : 0.0;
              final double avgPurchaseRate = fields.length > 14 ? (double.tryParse(fields[14].replaceAll('"', '').trim()) ?? 0.0) : 0.0;

              String cleanName = rawProductName;
              if (cleanName.isEmpty && saltGeneric.isNotEmpty) {
                cleanName = saltGeneric;
              }
              if (cleanName.isEmpty) continue;

              final String finalId = productId.isNotEmpty ? productId : 'PRD_$insertedCount';

              // Insert / Update into product_master without overwriting existing rates or rack locations
              batch.rawInsert('''
                INSERT INTO product_master (
                  id, name, generic_name, category_id, hsn_code, gst_percent,
                  packing, barcode, reorder_level, is_active, updated_at, is_imported, is_synced
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, 1, 0)
                ON CONFLICT(id) DO UPDATE SET
                  name = excluded.name,
                  generic_name = COALESCE(NULLIF(excluded.generic_name, ''), product_master.generic_name),
                  category_id = COALESCE(NULLIF(excluded.category_id, ''), product_master.category_id),
                  hsn_code = COALESCE(NULLIF(excluded.hsn_code, ''), product_master.hsn_code),
                  packing = CASE WHEN product_master.packing > 1 THEN product_master.packing ELSE excluded.packing END,
                  updated_at = excluded.updated_at,
                  is_synced = 0
              ''', [
                finalId,
                cleanName,
                saltGeneric,
                category,
                hsnCode,
                gstPercent,
                packingRatio,
                barcode,
                reorderLevel,
                nowIso,
              ]);

              // Insert / Replace into products table
              batch.rawInsert('''
                INSERT OR REPLACE INTO products (
                  id, name, generic_name, hsn_code, gst_percent, pack_size,
                  category, manufacturer, patent, mrp, purchase_rate, is_active, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
              ''', [
                finalId,
                cleanName,
                saltGeneric,
                hsnCode,
                gstPercent,
                packingRatio,
                category,
                manufacturer,
                brandCompany,
                avgMrp,
                avgPurchaseRate,
                nowIso,
              ]);

              insertedCount++;
            }

            await batch.commit(noResult: true);
          });

          rowBatch.clear();
          if (onProgress != null) {
            onProgress(insertedCount, totalRows);
          }
        }
      }

      debugPrint('Completed 57k product catalog import. Total inserted: $insertedCount');

      // Unpause sync and release lock before triggering automatic targeted cloud push
      SupabaseSyncService.instance.setBulkImportActive(false);

      if (ServerConfigService.instance.isServerModeEnabled) {
        SupabaseSyncService.instance.triggerInstantSync(
          isManualTransfer: true,
          selectedCategories: {'products'},
          isSilent: true,
        );
      }

      return {
        'success': true,
        'message': 'Successfully imported $insertedCount products with salt formulas and GST details.',
        'count': insertedCount,
      };
    } catch (e) {
      debugPrint('Error during 57k product catalog import: $e');
      return {
        'success': false,
        'message': 'Import failed: $e',
        'count': insertedCount,
      };
    } finally {
      SupabaseSyncService.instance.setBulkImportActive(false);
    }
  }

  /// Simple robust CSV line parser handling quoted fields containing commas
  List<String> _parseCsvLine(String line) {
    List<String> result = [];
    StringBuffer currentField = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(currentField.toString());
        currentField.clear();
      } else {
        currentField.write(char);
      }
    }
    result.add(currentField.toString());
    return result;
  }
}
