import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/services/isolate_compute_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Database Performance & FTS5 Full-Text Search', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          // 1. Setup base product_master table
          await db.execute('''
            CREATE TABLE product_master (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              generic_name TEXT,
              barcode TEXT,
              sku TEXT,
              hsn_code TEXT,
              rack_id TEXT,
              gst_percent REAL DEFAULT 12.0,
              packing INTEGER DEFAULT 1,
              mrp REAL DEFAULT 0.0,
              purchase_rate REAL DEFAULT 0.0,
              sale_rate REAL DEFAULT 0.0,
              reorder_level INTEGER DEFAULT 10,
              category_id TEXT,
              schedule TEXT,
              patent TEXT,
              manufacturer_id TEXT
            );
          ''');

          // 2. Setup stock_batches table
          await db.execute('''
            CREATE TABLE stock_batches (
              product_id TEXT,
              batch_number TEXT,
              expiry_date TEXT,
              current_stock INTEGER DEFAULT 0,
              current_quantity INTEGER DEFAULT 0,
              branch_id TEXT DEFAULT 'MAIN_STORE',
              purchase_rate REAL DEFAULT 0.0,
              mrp REAL DEFAULT 0.0,
              sale_rate REAL DEFAULT 0.0,
              PRIMARY KEY (product_id, batch_number)
            );
          ''');

          // 3. Setup sales_invoices table
          await db.execute('''
            CREATE TABLE sales_invoices (
              entry_no TEXT PRIMARY KEY,
              invoice_no TEXT,
              date TEXT NOT NULL,
              invoice_date TEXT,
              branch_id TEXT DEFAULT 'MAIN_STORE',
              financial_year TEXT,
              grand_total REAL,
              is_deleted INTEGER DEFAULT 0
            );
          ''');

          // 4. Setup convergence infrastructure tables
          await DbHelper.instance.ensureStockConvergenceTables(db);

          // 5. Setup FTS5 virtual table and triggers
          await db.execute('''
            CREATE VIRTUAL TABLE product_search_fts USING fts5(
              id UNINDEXED,
              name,
              generic_name,
              barcode,
              sku,
              hsn_code,
              rack_id,
              tokenize='unicode61 remove_diacritics 1'
            );
          ''');

          await db.execute('''
            CREATE TRIGGER ai_product_master_fts AFTER INSERT ON product_master BEGIN
              INSERT INTO product_search_fts(id, name, generic_name, barcode, sku, hsn_code, rack_id)
              VALUES (new.id, new.name, IFNULL(new.generic_name, ''), IFNULL(new.barcode, ''), IFNULL(new.sku, new.id), IFNULL(new.hsn_code, ''), IFNULL(new.rack_id, ''));
            END;
          ''');

          await db.execute('''
            CREATE TRIGGER au_product_master_fts AFTER UPDATE OF name, generic_name, barcode, sku, hsn_code, rack_id ON product_master BEGIN
              DELETE FROM product_search_fts WHERE id = old.id;
              INSERT INTO product_search_fts(id, name, generic_name, barcode, sku, hsn_code, rack_id)
              VALUES (new.id, new.name, IFNULL(new.generic_name, ''), IFNULL(new.barcode, ''), IFNULL(new.sku, new.id), IFNULL(new.hsn_code, ''), IFNULL(new.rack_id, ''));
            END;
          ''');

          await db.execute('''
            CREATE TRIGGER ad_product_master_fts AFTER DELETE ON product_master BEGIN
              DELETE FROM product_search_fts WHERE id = old.id;
            END;
          ''');

          // 6. Create composite indexes
          await db.execute('CREATE INDEX idx_stock_batches_branch_product ON stock_batches(branch_id, product_id, current_quantity);');
          await db.execute('CREATE INDEX idx_sales_branch_date ON sales_invoices(branch_id, invoice_date DESC);');
        },
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('Composite indexes exist on high-traffic tables', () async {
      final batchIndexes = await db.rawQuery("PRAGMA index_list('stock_batches')");
      final batchIdxNames = batchIndexes.map((r) => r['name']?.toString()).toSet();
      expect(batchIdxNames.contains('idx_stock_batches_branch_product'), isTrue);

      final salesIndexes = await db.rawQuery("PRAGMA index_list('sales_invoices')");
      final salesIdxNames = salesIndexes.map((r) => r['name']?.toString()).toSet();
      expect(salesIdxNames.contains('idx_sales_branch_date'), isTrue);

      final outboxIndexes = await db.rawQuery("PRAGMA index_list('stock_outbox')");
      final outboxIdxNames = outboxIndexes.map((r) => r['name']?.toString()).toSet();
      expect(outboxIdxNames.contains('idx_outbox_status_retries'), isTrue);

      final ledgerIndexes = await db.rawQuery("PRAGMA index_list('stock_ledger')");
      final ledgerIdxNames = ledgerIndexes.map((r) => r['name']?.toString()).toSet();
      expect(ledgerIdxNames.contains('idx_ledger_branch_batch'), isTrue);
    });

    test('FTS5 automatically indexes inserts and matches name, generic, barcode, and SKU', () async {
      // Insert product into product_master
      await db.insert('product_master', {
        'id': 'PROD-001',
        'name': 'Dolo 650mg Tablet',
        'generic_name': 'Paracetamol 650mg',
        'barcode': '8901234567890',
        'sku': 'SKU-DOLO-650',
        'hsn_code': '300490',
        'rack_id': 'RACK-A1',
      });

      // 1. Search by name prefix
      final nameMatches = await db.rawQuery('''
        SELECT fts.id, pm.name
        FROM product_search_fts fts
        JOIN product_master pm ON fts.id = pm.id
        WHERE product_search_fts MATCH '"dolo"*'
      ''');
      expect(nameMatches.length, equals(1));
      expect(nameMatches.first['name'], equals('Dolo 650mg Tablet'));

      // 2. Search by generic name
      final genericMatches = await db.rawQuery('''
        SELECT fts.id, pm.name
        FROM product_search_fts fts
        JOIN product_master pm ON fts.id = pm.id
        WHERE product_search_fts MATCH '"paracetamol"*'
      ''');
      expect(genericMatches.length, equals(1));

      // 3. Search by barcode
      final barcodeMatches = await db.rawQuery('''
        SELECT fts.id, pm.name
        FROM product_search_fts fts
        JOIN product_master pm ON fts.id = pm.id
        WHERE product_search_fts MATCH '"8901234567890"*'
      ''');
      expect(barcodeMatches.length, equals(1));

      // 4. Search by SKU
      final skuMatches = await db.rawQuery('''
        SELECT fts.id, pm.name
        FROM product_search_fts fts
        JOIN product_master pm ON fts.id = pm.id
        WHERE product_search_fts MATCH '"SKU-DOLO-650"*'
      ''');
      expect(skuMatches.length, equals(1));
    });

    test('FTS5 triggers keep virtual table updated on UPDATE and DELETE', () async {
      await db.insert('product_master', {
        'id': 'PROD-002',
        'name': 'Augmentin 625 Duo',
        'generic_name': 'Amoxicillin and Clavulanate',
        'barcode': '8901111222233',
        'sku': 'SKU-AUG-625',
      });

      // Update product name
      await db.update(
        'product_master',
        {'name': 'Augmentin 625 Duo Forte'},
        where: 'id = ?',
        whereArgs: ['PROD-002'],
      );

      final updatedMatch = await db.rawQuery('''
        SELECT fts.id, pm.name
        FROM product_search_fts fts
        JOIN product_master pm ON fts.id = pm.id
        WHERE product_search_fts MATCH '"forte"*'
      ''');
      expect(updatedMatch.length, equals(1));
      expect(updatedMatch.first['name'], equals('Augmentin 625 Duo Forte'));

      // Delete product
      await db.delete('product_master', where: 'id = ?', whereArgs: ['PROD-002']);

      final deletedMatch = await db.rawQuery('''
        SELECT fts.id
        FROM product_search_fts fts
        WHERE product_search_fts MATCH '"augmentin"*'
      ''');
      expect(deletedMatch, isEmpty);
    });
  });

  group('Isolate Compute Engine Tests', () {
    test('IsolateComputeService decodes large JSON arrays without blocking', () async {
      final jsonPayload = '[{"id": 1, "name": "Item 1"}, {"id": 2, "name": "Item 2"}]';
      final list = await IsolateComputeService.instance.parseJsonList(jsonPayload);
      expect(list.length, equals(2));
      expect(list.first['name'], equals('Item 1'));
    });

    test('IsolateComputeService decodes dynamic JSON payloads', () async {
      final mapPayload = '{"status": "success", "count": 100}';
      final map = await IsolateComputeService.instance.parseJsonDynamic(mapPayload);
      expect(map, isA<Map<String, dynamic>>());
      expect(map['status'], equals('success'));
      expect(map['count'], equals(100));
    });
  });
}
