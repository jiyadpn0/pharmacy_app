import 'dart:io';
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/erp_models.dart';
import '../utils/app_formatters.dart';
import '../services/server_config_service.dart';
import '../services/supabase_sync_service.dart';

class DbHelper {
  static final DbHelper instance = DbHelper._init();
  static Database? _database;
  static final _writeQueue = _AsyncWriteQueue();
  static bool _isBillingActive = false;
  static bool get isBillingActive => _isBillingActive;
  bool get isBillingActiveInstance => _isBillingActive;

  static void setBillingActive(bool active) {
    if (_isBillingActive != active) {
      _isBillingActive = active;
      debugPrint("DbHelper: Billing active mode set to $active");
    }
  }

  DbHelper._init();

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDB('pharmacy.db');
    return _database!;
  }

  /// Closes active SQLite database connection handle to release file locks
  Future<void> closeDatabase() async {
    if (_database != null) {
      try {
        await _database!.execute('PRAGMA wal_checkpoint(PASSIVE);');
        await _database!.close();
      } catch (e) {
        debugPrint("DbHelper closeDatabase notice: $e");
      }
      _database = null;
    }
  }

  /// Safely verifies and adds a column to a table if it does not already exist
  static Future<void> ensureColumnExists(
    Database db,
    String tableName,
    String columnName,
    String columnDef,
  ) async {
    try {
      final cols = await db.rawQuery('PRAGMA table_info($tableName)');
      if (!cols.any((c) => (c['name'] as String?)?.toLowerCase() == columnName.toLowerCase())) {
        await db.execute('ALTER TABLE $tableName ADD COLUMN $columnName $columnDef');
      }
    } catch (e) {
      debugPrint("ensureColumnExists ($tableName.$columnName) note: $e");
    }
  }

  /// Forces SQLite WAL Checkpoint to flush write logs and keep db compact
  Future<void> checkpointWal() async {
    try {
      final db = await database;
      await db.rawQuery('PRAGMA wal_checkpoint(PASSIVE);');
      debugPrint("SQLite WAL Checkpoint completed successfully.");
    } catch (e) {
      debugPrint("SQLite WAL Checkpoint Error: $e");
    }
  }

  /// Runs SQLite WAL checkpoint & page optimization without blocking active transactions
  Future<void> vacuumDatabase() async {
    try {
      final db = await database;
      await db.execute('PRAGMA wal_checkpoint(PASSIVE)');
      await db.execute('PRAGMA optimize');
      debugPrint("SQLite database optimization completed successfully.");
    } catch (e) {
      debugPrint("SQLite database Maintenance Error: $e");
    }
  }

  /// Automatically creates a daily local SQLite database backup copy
  /// Performs atomic VACUUM INTO database snapshot with fallback and integrity verification
  Future<bool> _createAtomicVerifiedSnapshot(File targetBackupFile) async {
    try {
      final db = await database;
      final escapedPath = targetBackupFile.path.replaceAll("'", "''");
      
      bool vacuumSuccess = false;
      try {
        await db.execute("VACUUM INTO '$escapedPath';");
        vacuumSuccess = await targetBackupFile.exists();
      } catch (vacuumErr) {
        debugPrint("VACUUM INTO note during auto-backup (fallback to WAL checkpoint): $vacuumErr");
      }

      if (!vacuumSuccess) {
        await checkpointWal();
        final dbPath = await getDatabasesPath();
        final sourceFile = File(join(dbPath, 'pharmacy.db'));
        if (await sourceFile.exists()) {
          await sourceFile.copy(targetBackupFile.path);
        }
      }

      // Verify backup integrity with PRAGMA quick_check
      if (await targetBackupFile.exists()) {
        try {
          final testDb = await openDatabase(targetBackupFile.path, readOnly: true);
          final res = await testDb.rawQuery('PRAGMA quick_check;');
          await testDb.close();
          if (res.isNotEmpty && res.first.values.first.toString().toLowerCase() == 'ok') {
            // Mirror snapshot to secondary USB / external folder if configured and reachable
            try {
              final prefs = await SharedPreferences.getInstance();
              final secPath = prefs.getString('secondary_backup_path') ?? '';
              if (secPath.isNotEmpty) {
                final secDir = Directory(secPath);
                if (await secDir.exists()) {
                  final secFile = File(join(secDir.path, basename(targetBackupFile.path)));
                  await targetBackupFile.copy(secFile.path);
                  debugPrint("Secondary USB/External backup mirror created: ${secFile.path}");
                }
              }
            } catch (secErr) {
              debugPrint("Secondary backup mirror notice: $secErr");
            }
            return true;
          }
        } catch (checkErr) {
          debugPrint("Integrity check failed for auto-backup snapshot: $checkErr");
        }
        // Integrity check failed, delete corrupt snapshot file
        if (await targetBackupFile.exists()) {
          await targetBackupFile.delete();
        }
        return false;
      }
      return false;
    } catch (e) {
      debugPrint("Error creating atomic snapshot: $e");
      return false;
    }
  }

  /// Automatically creates a daily local SQLite database backup copy using atomic WAL-safe snapshots.
  Future<void> autoBackupDatabase() async {
    try {
      if (kIsWeb) return;
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'pharmacy.db');
      final file = File(path);
      if (!await file.exists()) return;

      final docsDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(join(docsDir.path, 'backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final now = DateTime.now();
      final dateStr = "${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}";
      final backupPath = join(backupDir.path, 'pharmacy_backup_$dateStr.db');
      final backupFile = File(backupPath);

      if (!await backupFile.exists()) {
        final success = await _createAtomicVerifiedSnapshot(backupFile);
        if (success) {
          debugPrint("Automated daily database backup created & verified: $backupPath");
        }

        // Retain last 7 daily backup files
        final allEntities = await backupDir.list().toList();
        final backups = allEntities.whereType<File>().where((f) => f.path.endsWith('.db')).toList();
        if (backups.length > 7) {
          backups.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
          for (int i = 0; i < backups.length - 7; i++) {
            await backups[i].delete();
          }
        }
      }
    } catch (e) {
      debugPrint("Error creating auto database backup: $e");
    }
  }

  /// Automatically creates a timestamped database backup on application close using atomic WAL-safe snapshots.
  Future<void> autoBackupOnClose() async {
    try {
      if (kIsWeb) return;
      await checkpointWal();
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'pharmacy.db');
      final file = File(path);
      if (!await file.exists()) return;

      final docsDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(join(docsDir.path, 'backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final now = DateTime.now();
      final timestampStr = "${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}";
      final backupPath = join(backupDir.path, 'backup_$timestampStr.db');
      final backupFile = File(backupPath);

      final success = await _createAtomicVerifiedSnapshot(backupFile);
      if (success) {
        debugPrint("Auto-backup on close created & verified: $backupPath");
      }

      // Retain last 14 revisions/days of backups
      final allEntities = await backupDir.list().toList();
      final backups = allEntities.whereType<File>().where((f) => f.path.endsWith('.db')).toList();
      backups.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      if (backups.length > 14) {
        for (int i = 0; i < backups.length - 14; i++) {
          await backups[i].delete();
        }
      }
    } catch (e) {
      debugPrint("Error creating auto backup on close: $e");
    }
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    final db = await openDatabase(
      path,
      version: 80, // Incremented to 80 for pending_deletions table and cloud deletion locks
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
        await db.execute('PRAGMA journal_mode = WAL;');
        await db.execute('PRAGMA busy_timeout = 30000;'); // 30-second lock tolerance for heavy syncs
        await db.execute('PRAGMA synchronous = NORMAL;');
        await db.execute('PRAGMA read_uncommitted = true;'); // Enables instant non-blocking reads during background writes
        await db.execute('PRAGMA cache_size = -64000;'); // ~64MB Cache
        await db.execute('PRAGMA temp_store = MEMORY;');
        await db.execute('PRAGMA mmap_size = 536870912;'); // 512MB memory mapping
      },
    );

    try {
      await db.execute('PRAGMA journal_mode = WAL;');
      await db.execute('PRAGMA busy_timeout = 30000;'); // 30-second lock tolerance for heavy syncs
      await db.execute('PRAGMA synchronous = NORMAL;');
      await db.execute('PRAGMA read_uncommitted = true;');
    } catch (_) {}

    await checkAndMigrateColumns(db);
    await _ensureFtsSearch(db);
    await ensureStockConvergenceTables(db);
    await _ensurePerformanceIndexes(db);
    await cleanDuplicateLineItems(db);
    return db;
  }

  Future<void> cleanDuplicateLineItems(Database db) async {
    try {
      // 1. Deduplicate sales_items: keep lowest rowid for same (normalized invoice_no, product_id, batch_number, qty)
      await db.execute('''
        DELETE FROM sales_items 
        WHERE rowid NOT IN (
          SELECT MIN(rowid) 
          FROM sales_items 
          GROUP BY 
            CASE WHEN instr(invoice_no, '_') > 0 THEN substr(invoice_no, instr(invoice_no, '_') + 1) ELSE invoice_no END,
            product_id, 
            IFNULL(TRIM(batch_number), ''), 
            qty
        );
      ''');

      // 2. Deduplicate purchase_items: keep lowest rowid for same (normalized entry_no, product_id, batch, qty)
      await db.execute('''
        DELETE FROM purchase_items 
        WHERE rowid NOT IN (
          SELECT MIN(rowid) 
          FROM purchase_items 
          GROUP BY 
            CASE WHEN instr(entry_no, '_') > 0 THEN substr(entry_no, instr(entry_no, '_') + 1) ELSE entry_no END,
            product_id, 
            IFNULL(TRIM(batch), ''), 
            qty
        );
      ''');

      // 3. Deduplicate sales_return_items
      await db.execute('''
        DELETE FROM sales_return_items 
        WHERE rowid NOT IN (
          SELECT MIN(rowid) 
          FROM sales_return_items 
          GROUP BY 
            CASE WHEN instr(return_no, '_') > 0 THEN substr(return_no, instr(return_no, '_') + 1) ELSE return_no END,
            product_id, 
            IFNULL(TRIM(batch_number), ''), 
            quantity
        );
      ''');

      // 4. Deduplicate purchase_return_items
      await db.execute('''
        DELETE FROM purchase_return_items 
        WHERE rowid NOT IN (
          SELECT MIN(rowid) 
          FROM purchase_return_items 
          GROUP BY 
            CASE WHEN instr(entry_no, '_') > 0 THEN substr(entry_no, instr(entry_no, '_') + 1) ELSE entry_no END,
            product_name, 
            IFNULL(TRIM(batch), ''), 
            qty
        );
      ''');
    } catch (e) {
      debugPrint('cleanDuplicateLineItems error: $e');
    }
  }

  /// Ensures SQLite FTS5 (Full-Text Search) virtual table and triggers exist for instant sub-5ms search
  Future<void> _ensureFtsSearch(Database db) async {
    try {
      await ensureColumnExists(db, 'product_master', 'sku', 'TEXT');

      // Check if product_search_fts exists and has the required schema including sku
      bool needsRecreate = false;
      try {
        final tableInfo = await db.rawQuery('PRAGMA table_info(product_search_fts)');
        if (tableInfo.isEmpty) {
          needsRecreate = true;
        } else {
          final colNames = tableInfo.map((c) => c['name']?.toString()).toSet();
          if (!colNames.contains('sku')) {
            needsRecreate = true;
          }
        }
      } catch (_) {
        needsRecreate = true;
      }

      if (needsRecreate) {
        await db.execute('DROP TABLE IF EXISTS product_search_fts;');
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
      }

      await db.execute('DROP TRIGGER IF EXISTS ai_product_master_fts;');
      await db.execute('DROP TRIGGER IF EXISTS au_product_master_fts;');
      await db.execute('DROP TRIGGER IF EXISTS ad_product_master_fts;');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS ai_product_master_fts AFTER INSERT ON product_master BEGIN
          INSERT INTO product_search_fts(id, name, generic_name, barcode, sku, hsn_code, rack_id)
          VALUES (new.id, new.name, IFNULL(new.generic_name, ''), IFNULL(new.barcode, ''), IFNULL(new.sku, new.id), IFNULL(new.hsn_code, ''), IFNULL(new.rack_id, ''));
        END;
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS au_product_master_fts AFTER UPDATE OF name, generic_name, barcode, sku, hsn_code, rack_id ON product_master BEGIN
          DELETE FROM product_search_fts WHERE id = old.id;
          INSERT INTO product_search_fts(id, name, generic_name, barcode, sku, hsn_code, rack_id)
          VALUES (new.id, new.name, IFNULL(new.generic_name, ''), IFNULL(new.barcode, ''), IFNULL(new.sku, new.id), IFNULL(new.hsn_code, ''), IFNULL(new.rack_id, ''));
        END;
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS ad_product_master_fts AFTER DELETE ON product_master BEGIN
          DELETE FROM product_search_fts WHERE id = old.id;
        END;
      ''');

      // Populate FTS table if empty or if records were missing
      final ftsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM product_search_fts')) ?? 0;
      final masterCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM product_master')) ?? 0;
      if (ftsCount < masterCount || needsRecreate) {
        await db.execute('''
          INSERT INTO product_search_fts(id, name, generic_name, barcode, sku, hsn_code, rack_id)
          SELECT id, name, IFNULL(generic_name, ''), IFNULL(barcode, ''), IFNULL(sku, id), IFNULL(hsn_code, ''), IFNULL(rack_id, '')
          FROM product_master
          WHERE id NOT IN (SELECT id FROM product_search_fts);
        ''');
        debugPrint("DbHelper: Synchronized product_search_fts table with $masterCount records.");
      }
    } catch (ftsError) {
      debugPrint("DbHelper FTS5 Initialization Note: $ftsError");
    }
  }

  Future<void> _ensurePerformanceIndexes(Database db) async {
    try {
      // Ensure columns exist for composite performance indexes
      await ensureColumnExists(db, 'stock_batches', 'branch_id', "TEXT DEFAULT 'MAIN_STORE'");
      await ensureColumnExists(db, 'stock_batches', 'current_quantity', "INTEGER DEFAULT 0");
      try {
        await db.execute("UPDATE stock_batches SET current_quantity = current_stock WHERE (current_quantity = 0 OR current_quantity IS NULL) AND current_stock != 0;");
      } catch (_) {}

      await ensureColumnExists(db, 'sales_invoices', 'branch_id', "TEXT DEFAULT 'MAIN_STORE'");
      await ensureColumnExists(db, 'sales_invoices', 'invoice_date', "TEXT");
      try {
        await db.execute("UPDATE sales_invoices SET invoice_date = date WHERE (invoice_date IS NULL OR invoice_date = '') AND date IS NOT NULL;");
      } catch (_) {}

      await ensureColumnExists(db, 'stock_ledger', 'branch_id', "TEXT DEFAULT 'MAIN_STORE'");
      await ensureColumnExists(db, 'stock_ledger', 'batch_number', "TEXT");
      await ensureColumnExists(db, 'stock_ledger', 'created_at', "TEXT");
      try {
        await db.execute("UPDATE stock_ledger SET created_at = timestamp WHERE (created_at IS NULL OR created_at = '') AND timestamp IS NOT NULL;");
      } catch (_) {}

      // Composite indexes on high-traffic tables
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_batches_branch_product ON stock_batches(branch_id, product_id, current_quantity);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_branch_date ON sales_invoices(branch_id, invoice_date DESC);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_ledger_branch_batch ON stock_ledger(branch_id, batch_number, created_at DESC);');
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_outbox_status_retries ON stock_outbox(status, retry_count, created_at ASC);');
      } catch (_) {}

      // Enforce composite uniqueness to prevent cross-terminal duplicate entry insertions
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS uq_sales_inv_fy_entry ON sales_invoices(financial_year, entry_no);');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS uq_pur_entries_fy_entry ON purchase_entries(financial_year, entry_no);');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS uq_sales_ret_fy_entry ON sales_return_invoices(financial_year, entry_no);');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS uq_pur_ret_fy_entry ON purchase_return_entries(financial_year, entry_no);');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_inv_entry_fy ON sales_invoices(entry_no, financial_year);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_inv_fy_entry ON sales_invoices(financial_year, entry_no);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_inv_invno_fy ON sales_invoices(invoice_no, financial_year);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pur_entries_entry_fy ON purchase_entries(entry_no, financial_year);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pur_entries_fy_entry ON purchase_entries(financial_year, entry_no);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_ret_entry_fy ON sales_return_invoices(entry_no, financial_year);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pur_ret_entry_fy ON purchase_return_entries(entry_no, financial_year);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_adj_entry_fy ON stock_adjustments(entry_no, financial_year);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_ret_items ON sales_return_items(return_no);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pur_ret_items ON purchase_return_items(entry_no);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_adj_items ON stock_adjustment_items(adjustment_no);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pm_name ON product_master(name);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pm_barcode ON product_master(barcode);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sb_pid_batch ON stock_batches(product_id, batch_number);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sb_stock_consolidated ON stock_batches(product_id, current_stock, expiry_date);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_si_inv_pid ON sales_items(invoice_no, product_id);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_items_inv ON sales_items(invoice_no);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pi_entry_pid ON purchase_items(entry_no, product_id);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pur_items_entry ON purchase_items(entry_no);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_si_synced_updated ON sales_invoices(is_synced, updated_at);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pe_synced_updated ON purchase_entries(is_synced, updated_at);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sb_lookup_stock ON stock_batches(product_id, batch_number, current_stock);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_accounts_name ON accounts(account_name);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_items_prod_batch ON sales_items(product_id, batch_number);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pur_items_prod_batch ON purchase_items(product_id, batch);');

      // High-performance Date Range Indexes for Analysis Reports
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_inv_date_clean ON sales_invoices(date, is_deleted, customer_acc);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pur_entries_date_clean ON purchase_entries(date, is_deleted);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_ret_date_clean ON sales_return_invoices(date, is_deleted);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pur_ret_date_clean ON purchase_return_entries(date, is_deleted);');

      // One-time startup standardization for dates and financial years (offloaded from reporting queries)
      await db.rawUpdate('''
        UPDATE sales_invoices 
        SET date = substr(date, 7, 4) || '-' || substr(date, 4, 2) || '-' || substr(date, 1, 2) || 'T00:00:00.000'
        WHERE date LIKE '__/__/____%'
      ''');
      await db.rawUpdate('''
        UPDATE sales_invoices 
        SET financial_year = (
          CASE 
            WHEN CAST(strftime('%m', date) AS INTEGER) >= 4 
            THEN strftime('%Y', date) || '-' || substr(CAST(CAST(strftime('%Y', date) AS INTEGER) + 1 AS TEXT), 3, 2)
            ELSE CAST(CAST(strftime('%Y', date) AS INTEGER) - 1 AS TEXT) || '-' || substr(strftime('%Y', date), 3, 2)
          END
        )
        WHERE financial_year IS NULL OR financial_year = ''
      ''');
    } catch (_) {}
  }

  Future<void> checkAndMigrateColumns(Database db) async {
    if (ServerConfigService.instance.isWiping || SupabaseSyncService.instance.isWiping) return;
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS audit_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          action_type TEXT NOT NULL,
          invoice_no TEXT,
          user_name TEXT,
          details TEXT,
          timestamp TEXT NOT NULL
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS order_confirmations (
          order_id TEXT PRIMARY KEY,
          order_date TEXT NOT NULL,
          supplier_name TEXT NOT NULL,
          total_items INTEGER DEFAULT 0,
          total_amount REAL DEFAULT 0.0,
          status TEXT DEFAULT 'PENDING',
          expected_delivery_date TEXT,
          received_date TEXT,
          notes TEXT,
          created_at TEXT NOT NULL
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS order_confirmation_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          order_id TEXT NOT NULL,
          product_id TEXT,
          product_name TEXT NOT NULL,
          company TEXT,
          order_qty INTEGER DEFAULT 0,
          received_qty INTEGER DEFAULT 0,
          unit_price REAL DEFAULT 0.0,
          pack_size INTEGER DEFAULT 1,
          status TEXT DEFAULT 'PENDING',
          received_date TEXT,
          FOREIGN KEY (order_id) REFERENCES order_confirmations(order_id) ON DELETE CASCADE
        );
      ''');
    } catch (_) {}

    final syncTables = [
      'product_master',
      'stock_batches',
      'patients',
      'suppliers',
      'doctors',
      'categories',
      'manufacturers',
      'racks',
      'generics',
      'accounts',
      'staff',
      'prescriptions',
      'supplier_payments',
      'patient_payments',
      'supplier_credit_notes',
      'sales_invoices',
      'sales_items',
      'purchase_entries',
      'purchase_items',
      'sales_return_invoices',
      'sales_return_items',
      'purchase_return_entries',
      'purchase_return_items',
      'stock_adjustments',
      'stock_adjustment_items',
      'stock_write_offs',
      'order_confirmations',
      'ProductMappings',
      'edit_history_logs',
      'stock_ledger',
    ];
    for (var t in syncTables) {
      try {
        var cols = await db.rawQuery('PRAGMA table_info($t)');
        if (!cols.any((c) => c['name'] == 'is_synced')) {
          await db.execute('ALTER TABLE $t ADD COLUMN is_synced INTEGER DEFAULT 0');
        }
        if (!cols.any((c) => c['name'] == 'is_cloud_synced')) {
          await db.execute('ALTER TABLE $t ADD COLUMN is_cloud_synced INTEGER DEFAULT 0');
        }
        if (!cols.any((c) => c['name'] == 'updated_at')) {
          await db.execute('ALTER TABLE $t ADD COLUMN updated_at TEXT');
        }
        if (!cols.any((c) => c['name'] == 'is_deleted')) {
          await db.execute('ALTER TABLE $t ADD COLUMN is_deleted INTEGER DEFAULT 0');
        }
        if (!cols.any((c) => c['name'] == 'is_imported')) {
          await db.execute('ALTER TABLE $t ADD COLUMN is_imported INTEGER DEFAULT 0');
        }
      } catch (_) {}
    }

    try {
      final salesCols = await db.rawQuery('PRAGMA table_info(sales_invoices)');
      final salesColNames = salesCols.map((c) => c['name']?.toString()).toSet();
      if (!salesColNames.contains('done_by')) await db.execute('ALTER TABLE sales_invoices ADD COLUMN done_by TEXT');
      if (!salesColNames.contains('terminal_id')) await db.execute('ALTER TABLE sales_invoices ADD COLUMN terminal_id TEXT');
      if (!salesColNames.contains('shift_id')) await db.execute('ALTER TABLE sales_invoices ADD COLUMN shift_id TEXT');
      if (!salesColNames.contains('patient_age')) await db.execute('ALTER TABLE sales_invoices ADD COLUMN patient_age INTEGER');
      if (!salesColNames.contains('patient_gender')) await db.execute('ALTER TABLE sales_invoices ADD COLUMN patient_gender TEXT');
      if (!salesColNames.contains('patient_address')) await db.execute('ALTER TABLE sales_invoices ADD COLUMN patient_address TEXT');
      if (!salesColNames.contains('doctor_reg_no')) await db.execute('ALTER TABLE sales_invoices ADD COLUMN doctor_reg_no TEXT');
      if (!salesColNames.contains('gstin_number')) await db.execute('ALTER TABLE sales_invoices ADD COLUMN gstin_number TEXT');
      if (!salesColNames.contains('place_of_supply')) await db.execute('ALTER TABLE sales_invoices ADD COLUMN place_of_supply TEXT');
      if (!salesColNames.contains('discount_amount')) await db.execute('ALTER TABLE sales_invoices ADD COLUMN discount_amount REAL DEFAULT 0.0');
      if (!salesColNames.contains('e_way_bill_no')) await db.execute('ALTER TABLE sales_invoices ADD COLUMN e_way_bill_no TEXT');
      if (!salesColNames.contains('irn_number')) await db.execute('ALTER TABLE sales_invoices ADD COLUMN irn_number TEXT');

      final salesItemCols = await db.rawQuery('PRAGMA table_info(sales_items)');
      final salesItemColNames = salesItemCols.map((c) => c['name']?.toString()).toSet();
      if (!salesItemColNames.contains('f_qty')) await db.execute('ALTER TABLE sales_items ADD COLUMN f_qty INTEGER DEFAULT 0');
      if (!salesItemColNames.contains('hsn_code')) await db.execute('ALTER TABLE sales_items ADD COLUMN hsn_code TEXT');
      if (!salesItemColNames.contains('schedule')) await db.execute('ALTER TABLE sales_items ADD COLUMN schedule TEXT');
      if (!salesItemColNames.contains('terminal_id')) await db.execute("ALTER TABLE sales_items ADD COLUMN terminal_id TEXT DEFAULT 'POS-01'");

      final purCols = await db.rawQuery('PRAGMA table_info(purchase_entries)');
      final purColNames = purCols.map((c) => c['name']?.toString()).toSet();
      if (!purColNames.contains('supplier_gstin')) await db.execute('ALTER TABLE purchase_entries ADD COLUMN supplier_gstin TEXT');
      if (!purColNames.contains('credit_days')) await db.execute('ALTER TABLE purchase_entries ADD COLUMN credit_days INTEGER DEFAULT 0');
      if (!purColNames.contains('due_date')) await db.execute('ALTER TABLE purchase_entries ADD COLUMN due_date TEXT');
      if (!purColNames.contains('po_number')) await db.execute('ALTER TABLE purchase_entries ADD COLUMN po_number TEXT');
      if (!purColNames.contains('terminal_id')) await db.execute('ALTER TABLE purchase_entries ADD COLUMN terminal_id TEXT');
      if (!purColNames.contains('invoice_no')) await db.execute('ALTER TABLE purchase_entries ADD COLUMN invoice_no TEXT');

      final purItemCols = await db.rawQuery('PRAGMA table_info(purchase_items)');
      final purItemColNames = purItemCols.map((c) => c['name']?.toString()).toSet();
      if (!purItemColNames.contains('trade_disc_amt')) await db.execute('ALTER TABLE purchase_items ADD COLUMN trade_disc_amt REAL DEFAULT 0.0');
      if (!purItemColNames.contains('cash_disc_amt')) await db.execute('ALTER TABLE purchase_items ADD COLUMN cash_disc_amt REAL DEFAULT 0.0');
      if (!purItemColNames.contains('terminal_id')) await db.execute("ALTER TABLE purchase_items ADD COLUMN terminal_id TEXT DEFAULT 'POS-01'");

      try {
        await db.execute("ALTER TABLE sales_items ADD COLUMN terminal_id TEXT DEFAULT 'POS-01';");
      } catch (_) {}

      try {
        await db.execute("ALTER TABLE purchase_items ADD COLUMN terminal_id TEXT DEFAULT 'POS-01';");
      } catch (_) {}

      final adjCols = await db.rawQuery('PRAGMA table_info(stock_adjustments)');
      final adjColNames = adjCols.map((c) => c['name']?.toString()).toSet();
      if (!adjColNames.contains('valuation_loss')) await db.execute('ALTER TABLE stock_adjustments ADD COLUMN valuation_loss REAL DEFAULT 0.0');
      if (!adjColNames.contains('old_qty')) await db.execute('ALTER TABLE stock_adjustments ADD COLUMN old_qty INTEGER DEFAULT 0');
      if (!adjColNames.contains('new_qty')) await db.execute('ALTER TABLE stock_adjustments ADD COLUMN new_qty INTEGER DEFAULT 0');
      if (!adjColNames.contains('reason_code')) await db.execute('ALTER TABLE stock_adjustments ADD COLUMN reason_code TEXT');

      final writeOffCols = await db.rawQuery('PRAGMA table_info(stock_write_offs)');
      final writeOffColNames = writeOffCols.map((c) => c['name']?.toString()).toSet();
      if (!writeOffColNames.contains('is_claimable')) await db.execute('ALTER TABLE stock_write_offs ADD COLUMN is_claimable INTEGER DEFAULT 0');
      if (!writeOffColNames.contains('manufacturer_id')) await db.execute('ALTER TABLE stock_write_offs ADD COLUMN manufacturer_id TEXT');
      if (!writeOffColNames.contains('claim_status')) await db.execute('ALTER TABLE stock_write_offs ADD COLUMN claim_status TEXT DEFAULT "UNCLAIMED"');

      final patCols = await db.rawQuery('PRAGMA table_info(patients)');
      final patColNames = patCols.map((c) => c['name']?.toString()).toSet();
      if (!patColNames.contains('gstin')) await db.execute('ALTER TABLE patients ADD COLUMN gstin TEXT');
      if (!patColNames.contains('credit_limit')) await db.execute('ALTER TABLE patients ADD COLUMN credit_limit REAL DEFAULT 0.0');
      if (!patColNames.contains('chronic_disease_tags')) await db.execute('ALTER TABLE patients ADD COLUMN chronic_disease_tags TEXT');

      final supCols = await db.rawQuery('PRAGMA table_info(suppliers)');
      final supColNames = supCols.map((c) => c['name']?.toString()).toSet();
      if (!supColNames.contains('dl_number_20b')) await db.execute('ALTER TABLE suppliers ADD COLUMN dl_number_20b TEXT');
      if (!supColNames.contains('dl_number_21b')) await db.execute('ALTER TABLE suppliers ADD COLUMN dl_number_21b TEXT');
      if (!supColNames.contains('dl_expiry_date')) await db.execute('ALTER TABLE suppliers ADD COLUMN dl_expiry_date TEXT');
      if (!supColNames.contains('fssai_no')) await db.execute('ALTER TABLE suppliers ADD COLUMN fssai_no TEXT');
      if (!supColNames.contains('bank_account_no')) await db.execute('ALTER TABLE suppliers ADD COLUMN bank_account_no TEXT');
      if (!supColNames.contains('bank_ifsc')) await db.execute('ALTER TABLE suppliers ADD COLUMN bank_ifsc TEXT');
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('schema_v78_migrated_done') == true) {
      return; // Skip on startup once migrated. Bypasses 15-second DB scan!
    }

    // Safety checks: ensure crucial tables exist
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_deletions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT NOT NULL,
          entry_no TEXT NOT NULL,
          deleted_at TEXT NOT NULL,
          is_synced INTEGER DEFAULT 0,
          UNIQUE(table_name, entry_no)
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_del_synced ON pending_deletions(is_synced);');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_deletions_queue (
          id TEXT PRIMARY KEY,
          table_name TEXT NOT NULL,
          record_id TEXT NOT NULL,
          deleted_at TEXT NOT NULL,
          is_synced INTEGER DEFAULT 0
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_del_synced ON sync_deletions_queue(is_synced);');

      // Draft Bills table for instant auto-drafting and power-cut recovery
      await db.execute('''
        CREATE TABLE IF NOT EXISTS draft_bills (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          draft_key TEXT UNIQUE NOT NULL,
          form_type TEXT NOT NULL,
          data_json TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_draft_key ON draft_bills(draft_key);');

      // Parked Sales table for Multi-Counter Bill Parking (F4/F5)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS parked_sales (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          park_key TEXT UNIQUE NOT NULL,
          customer_name TEXT,
          data_json TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_park_key ON parked_sales(park_key);');

      // FTS5 Virtual Table for Instant Local Medicine Search (< 1ms)
      await _ensureFtsSearch(db);

      // Create new Ledger Engine tables
      await db.execute('''
        CREATE TABLE IF NOT EXISTS batch_master (
          batch_id TEXT PRIMARY KEY,
          product_id TEXT NOT NULL,
          batch_number TEXT NOT NULL,
          expiry_date TEXT NOT NULL,
          mfg_date TEXT,
          supplier_id TEXT,
          supplier_name TEXT,
          packing INTEGER DEFAULT 1,
          purchase_rate REAL DEFAULT 0.0,
          landing_cost REAL DEFAULT 0.0,
          mrp REAL DEFAULT 0.0,
          sale_rate REAL DEFAULT 0.0,
          gst_percent REAL DEFAULT 12.0,
          rack TEXT,
          created_at TEXT NOT NULL,
          is_active INTEGER DEFAULT 1,
          FOREIGN KEY (product_id) REFERENCES product_master (id)
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_ledger (
          ledger_id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT NOT NULL,
          batch_id TEXT NOT NULL,
          product_id TEXT NOT NULL,
          voucher_type TEXT NOT NULL,
          voucher_no TEXT NOT NULL,
          qty_in INTEGER DEFAULT 0,
          qty_out INTEGER DEFAULT 0,
          purchase_rate REAL DEFAULT 0.0,
          mrp REAL DEFAULT 0.0,
          supplier_name TEXT,
          remarks TEXT,
          user_id TEXT DEFAULT 'Admin',
          financial_year TEXT,
          FOREIGN KEY (batch_id) REFERENCES batch_master (batch_id),
          FOREIGN KEY (product_id) REFERENCES product_master (id)
        )
      ''');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_bm_prod_exp ON batch_master(product_id, expiry_date);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_bm_lookup ON batch_master(product_id, batch_number);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sl_batch ON stock_ledger(batch_id);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sl_prod ON stock_ledger(product_id);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sl_vouch ON stock_ledger(voucher_type, voucher_no);');

      await _migrateLegacyBatchesToBatchMaster(db);
    } catch (e) {
      debugPrint("DB Safety Update Note: $e");
    }

    // Always clean up any duplicate sales_items, purchase_items, or stock_batches entries
    if (!ServerConfigService.instance.isWiping && !SupabaseSyncService.instance.isWiping) {
      await cleanupDuplicateItems(db);
    }

    try {
      var purCols = await db.rawQuery('PRAGMA table_info(purchase_entries)');
      if (!purCols.any((c) => c['name'] == 'tax_type')) {
        await db.execute("ALTER TABLE purchase_entries ADD COLUMN tax_type TEXT DEFAULT 'Gst'");
      }
    } catch (e) {
      debugPrint("DB Check PurchaseEntries Note: $e");
    }

    try {
      var saleCols = await db.rawQuery('PRAGMA table_info(sales_invoices)');
      if (!saleCols.any((c) => c['name'] == 'order_type')) {
        await db.execute("ALTER TABLE sales_invoices ADD COLUMN order_type INTEGER DEFAULT 0");
      }
      if (!saleCols.any((c) => c['name'] == 'entry_num')) {
        await db.execute("ALTER TABLE sales_invoices ADD COLUMN entry_num INTEGER");
      }
      if (!saleCols.any((c) => c['name'] == 'financial_year')) {
        await db.execute("ALTER TABLE sales_invoices ADD COLUMN financial_year TEXT");
      }
      if (!saleCols.any((c) => c['name'] == 'secondary_acc')) {
        await db.execute("ALTER TABLE sales_invoices ADD COLUMN secondary_acc TEXT");
      }
      if (!saleCols.any((c) => c['name'] == 'secondary_amt')) {
        await db.execute("ALTER TABLE sales_invoices ADD COLUMN secondary_amt REAL DEFAULT 0.0");
      }
      if (!saleCols.any((c) => c['name'] == 'sales_return_amt')) {
        await db.execute("ALTER TABLE sales_invoices ADD COLUMN sales_return_amt REAL DEFAULT 0.0");
      }
      if (!saleCols.any((c) => c['name'] == 'is_deleted')) {
        await db.execute("ALTER TABLE sales_invoices ADD COLUMN is_deleted INTEGER DEFAULT 0");
      }
    } catch (e) {
      debugPrint("DB Check SalesInvoices Note: $e");
    }

    try {
      var preCols = await db.rawQuery('PRAGMA table_info(purchase_return_entries)');
      if (!preCols.any((c) => c['name'] == 'gst_mode')) {
        await db.execute("ALTER TABLE purchase_return_entries ADD COLUMN gst_mode INTEGER DEFAULT 1");
      }
      if (!preCols.any((c) => c['name'] == 'original_purchase_no')) {
        await db.execute("ALTER TABLE purchase_return_entries ADD COLUMN original_purchase_no TEXT");
      }
      if (!preCols.any((c) => c['name'] == 'done_by')) {
        await db.execute("ALTER TABLE purchase_return_entries ADD COLUMN done_by TEXT");
      }
      if (!preCols.any((c) => c['name'] == 'is_deleted')) {
        await db.execute("ALTER TABLE purchase_return_entries ADD COLUMN is_deleted INTEGER DEFAULT 0");
      }
      if (!preCols.any((c) => c['name'] == 'is_imported')) {
        await db.execute("ALTER TABLE purchase_return_entries ADD COLUMN is_imported INTEGER DEFAULT 0");
      }
      if (!preCols.any((c) => c['name'] == 'financial_year')) {
        await db.execute("ALTER TABLE purchase_return_entries ADD COLUMN financial_year TEXT");
      }
    } catch (e) {
      debugPrint("DB Check PurchaseReturn Note: $e");
    }

    try {
      var salesItemCols = await db.rawQuery('PRAGMA table_info(sales_items)');
      if (!salesItemCols.any((c) => c['name'] == 'rack')) {
        await db.execute("ALTER TABLE sales_items ADD COLUMN rack TEXT");
      }
      if (!salesItemCols.any((c) => c['name'] == 'purchase_rate')) {
        await db.execute("ALTER TABLE sales_items ADD COLUMN purchase_rate REAL DEFAULT 0.0");
      }
      if (!salesItemCols.any((c) => c['name'] == 'supplier_name')) {
        await db.execute("ALTER TABLE sales_items ADD COLUMN supplier_name TEXT");
      }
      if (!salesItemCols.any((c) => c['name'] == 'landing_cost')) {
        await db.execute("ALTER TABLE sales_items ADD COLUMN landing_cost REAL DEFAULT 0.0");
      }
    } catch (e) {
      debugPrint("DB Check SalesItems Note: $e");
    }

    try {
      var pmCols = await db.rawQuery('PRAGMA table_info(product_master)');
      if (!pmCols.any((c) => c['name'] == 'rack_id')) {
        await db.execute("ALTER TABLE product_master ADD COLUMN rack_id TEXT");
      }
    } catch (e) {
      debugPrint("DB Check PM Note: $e");
    }

    if (prefs.getBool('schema_v75_migrated_done') == true) {
      return; // Skip on startup once migrated. Prevents 15-second DB write lock!
    }

    await db.transaction((txn) async {
      // 0. Auto-clean any purchase_entries scientific notation invoice numbers
      try {
        final dirtyRows = await txn.rawQuery("SELECT entry_no, sup_inv_no FROM purchase_entries WHERE sup_inv_no LIKE '%E+%' OR sup_inv_no LIKE '%e+%' OR sup_inv_no LIKE '%.0'");
        for (var row in dirtyRows) {
          String raw = row['sup_inv_no']?.toString() ?? "";
          String entryNo = row['entry_no']?.toString() ?? "";
          String cleaned = cleanInvoiceNo(raw);
          if (cleaned.isNotEmpty && cleaned != raw && entryNo.isNotEmpty) {
            await txn.rawUpdate("UPDATE purchase_entries SET sup_inv_no = ? WHERE entry_no = ?", [cleaned, entryNo]);
          }
        }
      } catch (_) {}

      // 1. Purchase Return Entries
      try {
        await txn.execute("ALTER TABLE purchase_return_entries ADD COLUMN original_purchase_no TEXT;");
      } catch (_) {}
      try {
        await txn.execute("ALTER TABLE purchase_return_entries ADD COLUMN done_by TEXT;");
      } catch (_) {}
      try {
        await txn.execute("ALTER TABLE purchase_return_entries ADD COLUMN gst_mode INTEGER DEFAULT 1;");
      } catch (_) {}
      try {
        await txn.execute("ALTER TABLE purchase_return_entries ADD COLUMN is_deleted INTEGER DEFAULT 0;");
      } catch (_) {}
      try {
        await txn.execute("ALTER TABLE purchase_return_entries ADD COLUMN is_imported INTEGER DEFAULT 0;");
      } catch (_) {}
      try {
        await txn.execute("ALTER TABLE purchase_return_entries ADD COLUMN financial_year TEXT;");
      } catch (_) {}

      // 2. Purchase Return Items
      try {
        var cols = await txn.rawQuery('PRAGMA table_info(purchase_return_items)');
        if (!cols.any((c) => c['name'] == 'packin')) await txn.execute('ALTER TABLE purchase_return_items ADD COLUMN packin INTEGER DEFAULT 1');
        if (!cols.any((c) => c['name'] == 'unit')) await txn.execute('ALTER TABLE purchase_return_items ADD COLUMN unit TEXT DEFAULT "BULK"');
        if (!cols.any((c) => c['name'] == 'qty')) await txn.execute('ALTER TABLE purchase_return_items ADD COLUMN qty INTEGER DEFAULT 0');
        if (!cols.any((c) => c['name'] == 'loose_qty')) await txn.execute('ALTER TABLE purchase_return_items ADD COLUMN loose_qty INTEGER DEFAULT 0');
        if (!cols.any((c) => c['name'] == 'f_qty')) await txn.execute('ALTER TABLE purchase_return_items ADD COLUMN f_qty INTEGER DEFAULT 0');
        if (!cols.any((c) => c['name'] == 'disc_percent')) await txn.execute('ALTER TABLE purchase_return_items ADD COLUMN disc_percent REAL DEFAULT 0.0');
        if (!cols.any((c) => c['name'] == 'gst_percent')) await txn.execute('ALTER TABLE purchase_return_items ADD COLUMN gst_percent REAL DEFAULT 0.0');
        if (!cols.any((c) => c['name'] == 'reason')) await txn.execute('ALTER TABLE purchase_return_items ADD COLUMN reason TEXT');
        if (!cols.any((c) => c['name'] == 'supplier')) await txn.execute('ALTER TABLE purchase_return_items ADD COLUMN supplier TEXT');
        if (!cols.any((c) => c['name'] == 'hsn_code')) await txn.execute('ALTER TABLE purchase_return_items ADD COLUMN hsn_code TEXT');
        if (!cols.any((c) => c['name'] == 's_rate')) await txn.execute('ALTER TABLE purchase_return_items ADD COLUMN s_rate REAL DEFAULT 0.0');
        if (!cols.any((c) => c['name'] == 'sup_inv_no')) await txn.execute('ALTER TABLE purchase_return_items ADD COLUMN sup_inv_no TEXT');
      } catch (_) {}

      // 3. Stock Batches
      try {
        var batchCols = await txn.rawQuery('PRAGMA table_info(stock_batches)');
        if (!batchCols.any((c) => c['name'] == 'packing')) {
          await txn.execute('ALTER TABLE stock_batches ADD COLUMN packing INTEGER DEFAULT 1');
        }
        if (!batchCols.any((c) => c['name'] == 'supplier_name')) {
          await txn.execute('ALTER TABLE stock_batches ADD COLUMN supplier_name TEXT');
        }
        if (!batchCols.any((c) => c['name'] == 'landing_cost')) {
          await txn.execute('ALTER TABLE stock_batches ADD COLUMN landing_cost REAL DEFAULT 0.0');
        }
        if (!batchCols.any((c) => c['name'] == 'gst_percent')) {
          await txn.execute('ALTER TABLE stock_batches ADD COLUMN gst_percent REAL DEFAULT 12.0');
        }
        if (!batchCols.any((c) => c['name'] == 'financial_year')) {
          await txn.execute('ALTER TABLE stock_batches ADD COLUMN financial_year TEXT');
        }
      } catch (_) {}

      // 4. Sales Invoices
      try {
        var saleCols = await txn.rawQuery('PRAGMA table_info(sales_invoices)');
        if (!saleCols.any((c) => c['name'] == 'sales_return_amt')) {
          await txn.execute("ALTER TABLE sales_invoices ADD COLUMN sales_return_amt REAL DEFAULT 0.0");
        }
        if (!saleCols.any((c) => c['name'] == 'financial_year')) {
          await txn.execute("ALTER TABLE sales_invoices ADD COLUMN financial_year TEXT");
        }
        if (!saleCols.any((c) => c['name'] == 'secondary_acc')) {
          await txn.execute("ALTER TABLE sales_invoices ADD COLUMN secondary_acc TEXT");
        }
        if (!saleCols.any((c) => c['name'] == 'secondary_amt')) {
          await txn.execute("ALTER TABLE sales_invoices ADD COLUMN secondary_amt REAL DEFAULT 0.0");
        }
        if (!saleCols.any((c) => c['name'] == 'is_deleted')) {
          await txn.execute("ALTER TABLE sales_invoices ADD COLUMN is_deleted INTEGER DEFAULT 0");
        }
        if (!saleCols.any((c) => c['name'] == 'order_type')) {
          await txn.execute("ALTER TABLE sales_invoices ADD COLUMN order_type INTEGER DEFAULT 0");
        }
        if (!saleCols.any((c) => c['name'] == 'entry_num')) {
          await txn.execute("ALTER TABLE sales_invoices ADD COLUMN entry_num INTEGER");
        }
      } catch (_) {}

      // 5. Sales Items
      try {
        var salesItemCols = await txn.rawQuery('PRAGMA table_info(sales_items)');
        if (!salesItemCols.any((c) => c['name'] == 'cgst_amt')) await txn.execute("ALTER TABLE sales_items ADD COLUMN cgst_amt REAL DEFAULT 0.0");
        if (!salesItemCols.any((c) => c['name'] == 'sgst_amt')) await txn.execute("ALTER TABLE sales_items ADD COLUMN sgst_amt REAL DEFAULT 0.0");
        if (!salesItemCols.any((c) => c['name'] == 'igst_amt')) await txn.execute("ALTER TABLE sales_items ADD COLUMN igst_amt REAL DEFAULT 0.0");
        if (!salesItemCols.any((c) => c['name'] == 'purchase_rate')) await txn.execute("ALTER TABLE sales_items ADD COLUMN purchase_rate REAL DEFAULT 0.0");
        if (!salesItemCols.any((c) => c['name'] == 'supplier_name')) await txn.execute("ALTER TABLE sales_items ADD COLUMN supplier_name TEXT");
        if (!salesItemCols.any((c) => c['name'] == 'landing_cost')) await txn.execute("ALTER TABLE sales_items ADD COLUMN landing_cost REAL DEFAULT 0.0");
        if (!salesItemCols.any((c) => c['name'] == 'rack')) await txn.execute("ALTER TABLE sales_items ADD COLUMN rack TEXT");
      } catch (_) {}

      // 6. Sales Return Invoices & Items
      try {
        var sriHeaderCols = await txn.rawQuery('PRAGMA table_info(sales_return_invoices)');
        if (!sriHeaderCols.any((c) => c['name'] == 'is_imported')) {
          await txn.execute("ALTER TABLE sales_return_invoices ADD COLUMN is_imported INTEGER DEFAULT 0");
        }
        if (!sriHeaderCols.any((c) => c['name'] == 'sub_total')) {
          await txn.execute("ALTER TABLE sales_return_invoices ADD COLUMN sub_total REAL DEFAULT 0.0");
        }
        if (!sriHeaderCols.any((c) => c['name'] == 'round_off')) {
          await txn.execute("ALTER TABLE sales_return_invoices ADD COLUMN round_off REAL DEFAULT 0.0");
        }
        if (!sriHeaderCols.any((c) => c['name'] == 'narration')) {
          await txn.execute("ALTER TABLE sales_return_invoices ADD COLUMN narration TEXT");
        }
        if (!sriHeaderCols.any((c) => c['name'] == 'gst_mode')) {
          await txn.execute("ALTER TABLE sales_return_invoices ADD COLUMN gst_mode INTEGER DEFAULT 1");
        }

        var sriCols = await txn.rawQuery('PRAGMA table_info(sales_return_items)');
        if (!sriCols.any((c) => c['name'] == 'purchase_rate')) await txn.execute("ALTER TABLE sales_return_items ADD COLUMN purchase_rate REAL DEFAULT 0.0");
        if (!sriCols.any((c) => c['name'] == 'supplier_name')) await txn.execute("ALTER TABLE sales_return_items ADD COLUMN supplier_name TEXT");
        if (!sriCols.any((c) => c['name'] == 'landing_cost')) await txn.execute("ALTER TABLE sales_return_items ADD COLUMN landing_cost REAL DEFAULT 0.0");
        if (!sriCols.any((c) => c['name'] == 'packing')) await txn.execute("ALTER TABLE sales_return_items ADD COLUMN packing INTEGER DEFAULT 1");
        if (!sriCols.any((c) => c['name'] == 'gst_percent')) await txn.execute("ALTER TABLE sales_return_items ADD COLUMN gst_percent REAL DEFAULT 12.0");
        if (!sriCols.any((c) => c['name'] == 'disc_percent')) await txn.execute("ALTER TABLE sales_return_items ADD COLUMN disc_percent REAL DEFAULT 0.0");
        if (!sriCols.any((c) => c['name'] == 'disc_amt')) await txn.execute("ALTER TABLE sales_return_items ADD COLUMN disc_amt REAL DEFAULT 0.0");
        if (!sriCols.any((c) => c['name'] == 'hsn_code')) await txn.execute("ALTER TABLE sales_return_items ADD COLUMN hsn_code TEXT");
      } catch (_) {}

      // 7. Audit Logs User ID
      try {
        var auditCols = await txn.rawQuery('PRAGMA table_info(system_audit_logs)');
        if (!auditCols.any((c) => c['name'] == 'user_id')) {
          await txn.execute("ALTER TABLE system_audit_logs ADD COLUMN user_id TEXT DEFAULT 'Admin'");
        }
      } catch (_) {}

      // 8. Apply High-Speed Performance Indexes
      try {
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_sales_date_fy ON sales_invoices(date, financial_year, is_deleted);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pur_date_fy ON purchase_entries(date, financial_year, is_deleted);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_sales_items_inv ON sales_items(invoice_no);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_sales_items_prod ON sales_items(product_id);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pur_items_entry ON purchase_items(entry_no);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pur_items_prod ON purchase_items(product_id);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_batches_prod ON stock_batches(product_id);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_batches_exp ON stock_batches(expiry_date);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_prod_master_name ON product_master(name);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_prod_master_generic ON product_master(generic_name);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_monthly_close ON monthly_closing_balances(closing_month_year);');
      } catch (_) {}

      // 9. Extra High-Speed Performance Indexes for Orders & Ranking & Date Sanitation
      try {
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_sales_items_prod_qty ON sales_items(product_id, qty);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_sales_items_name ON sales_items(product_name);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_sales_invoices_entry_date ON sales_invoices(entry_no, date, is_deleted);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_sales_invoices_fy_num ON sales_invoices(financial_year, entry_num);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pur_items_prod_qty ON purchase_items(product_id, qty);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pur_entries_entry_date ON purchase_entries(entry_no, date, is_deleted);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_batches_name ON stock_batches(product_name);');
        await txn.execute("UPDATE sales_invoices SET date = substr(date, 7, 4) || '-' || substr(date, 4, 2) || '-' || substr(date, 1, 2) || 'T00:00:00.000' WHERE date LIKE '__/__/____%';");
        await txn.execute("UPDATE sales_invoices SET entry_num = CAST(CASE WHEN instr(entry_no, '_') > 0 THEN substr(entry_no, instr(entry_no, '_') + 1) ELSE REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(entry_no, 'SRET-', ''), 'PRET-', ''), 'ADJ-', ''), 'ORD-', ''), 'SO-', '') END AS INTEGER) WHERE entry_num IS NULL;");
      } catch (_) {}

      // 10. Performance Indexes for 50k+ Product Master & Batch Lookups
      try {
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pm_name_nocase ON product_master(name COLLATE NOCASE);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pm_generic_nocase ON product_master(generic_name COLLATE NOCASE);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pm_hsn ON product_master(hsn_code);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pm_barcode ON product_master(barcode);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pm_schedule_h1 ON product_master(schedule_h1);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_sb_prod_stock ON stock_batches(product_id, current_stock);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_sb_batch_nocase ON stock_batches(batch_number COLLATE NOCASE);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_sales_items_inv_prod ON sales_items(invoice_no, product_id);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_sales_items_pname_nocase ON sales_items(product_name COLLATE NOCASE);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pur_items_entry_prod ON purchase_items(entry_no, product_id);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pur_items_pname_nocase ON purchase_items(product_name COLLATE NOCASE);');
      } catch (_) {}

      // 11. Order Confirmation Tables
      try {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS order_confirmations (
            order_id TEXT PRIMARY KEY,
            order_date TEXT NOT NULL,
            supplier_name TEXT NOT NULL,
            total_items INTEGER DEFAULT 0,
            total_amount REAL DEFAULT 0.0,
            status TEXT DEFAULT 'PENDING',
            expected_delivery_date TEXT,
            received_date TEXT,
            notes TEXT,
            created_at TEXT NOT NULL
          );
        ''');
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS order_confirmation_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id TEXT NOT NULL,
            product_id TEXT,
            product_name TEXT NOT NULL,
            company TEXT,
            order_qty INTEGER DEFAULT 0,
            received_qty INTEGER DEFAULT 0,
            unit_price REAL DEFAULT 0.0,
            pack_size INTEGER DEFAULT 1,
            status TEXT DEFAULT 'PENDING',
            received_date TEXT,
            FOREIGN KEY (order_id) REFERENCES order_confirmations(order_id) ON DELETE CASCADE
          );
        ''');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_order_conf_date ON order_confirmations(order_date);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_order_conf_status ON order_confirmations(status);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_order_conf_items_ord ON order_confirmation_items(order_id);');
      } catch (_) {}

      // Product Name Cleanup Migration
      try {
        await txn.rawUpdate(
          "UPDATE product_master SET name = TRIM(TRIM(TRIM(name), '\"'), ''''), generic_name = TRIM(TRIM(TRIM(generic_name), '\"'), '''') WHERE name LIKE '\"%' OR name LIKE '''%' OR name LIKE ' %' OR generic_name LIKE '\"%' OR generic_name LIKE '''%' OR generic_name LIKE ' %';",
        );
        await txn.rawUpdate(
          "UPDATE stock_batches SET batch_number = TRIM(TRIM(TRIM(batch_number), '\"'), '''') WHERE batch_number LIKE '\"%' OR batch_number LIKE '''%' OR batch_number LIKE ' %';",
        );
        // Entry Number Sanitization Migration
        await txn.execute('''
          UPDATE sales_invoices 
          SET entry_no = CAST(CASE WHEN instr(entry_no, '_') > 0 THEN substr(entry_no, instr(entry_no, '_') + 1) ELSE entry_no END AS TEXT)
          WHERE entry_no LIKE '%\\_%' ESCAPE '\\';
        ''');
      } catch (e) {
        debugPrint("Product name migration note: $e");
      }

      await prefs.setBool('schema_v75_migrated_done', true);
      await prefs.setBool('schema_v77_migrated_done', true);
      await prefs.setBool('schema_v78_migrated_done', true);
    });
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      try { await db.execute('ALTER TABLE product_master ADD COLUMN sub_category_id TEXT'); } catch (_) {}
    }
    if (oldVersion < 4) {
      try { await db.execute('ALTER TABLE product_master ADD COLUMN s_disc_percent REAL DEFAULT 0.0'); } catch (_) {}
    }
    if (oldVersion < 5) {
      try { await db.execute('ALTER TABLE sales_items ADD COLUMN extra TEXT'); } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        var columns = await db.rawQuery('PRAGMA table_info(product_master)');
        if (!columns.any((c) => c['name'] == 'patent')) {
          await db.execute('ALTER TABLE product_master ADD COLUMN patent TEXT');
        }
      } catch (_) {}
    }
    if (oldVersion < 9) {
      try { await db.execute('ALTER TABLE racks ADD COLUMN is_active INTEGER DEFAULT 1'); } catch (_) {}
    }
    if (oldVersion < 10) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS rack_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id TEXT,
            product_name TEXT,
            old_rack TEXT,
            new_rack TEXT,
            change_date TEXT
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 11) {
      try {
        await db.execute('ALTER TABLE purchase_entries ADD COLUMN payment_status INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE purchase_entries ADD COLUMN payment_mode TEXT');
        await db.execute('ALTER TABLE purchase_entries ADD COLUMN payment_remarks TEXT');
        await db.execute('ALTER TABLE purchase_entries ADD COLUMN payment_date TEXT');
      } catch (_) {}
    }
    if (oldVersion < 12) {
      try {
        var columns = await db.rawQuery('PRAGMA table_info(purchase_items)');
        if (!columns.any((c) => c['name'] == 'extra')) {
          await db.execute('ALTER TABLE purchase_items ADD COLUMN extra TEXT');
        }
      } catch (_) {}
    }
    if (oldVersion < 13) {
      try { await db.execute('ALTER TABLE purchase_entries ADD COLUMN paid_amount REAL DEFAULT 0.0'); } catch (_) {}
    }
    if (oldVersion < 14) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS supplier_payments (
            id TEXT PRIMARY KEY,
            supplier_name TEXT,
            date TEXT,
            amount REAL,
            invoice_no TEXT,
            payment_method TEXT,
            remarks TEXT
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 15) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS supplier_credit_notes (
            id TEXT PRIMARY KEY,
            supplier_name TEXT,
            date TEXT,
            amount REAL,
            invoice_no TEXT,
            remarks TEXT
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 38) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ProductMappings(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            wholesaler_name TEXT,
            external_code TEXT,
            external_name TEXT,
            internal_name TEXT,
            product_id TEXT
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 39) {
      try { await db.execute('ALTER TABLE ProductMappings ADD COLUMN external_code TEXT'); } catch (_) {}
    }
    if (oldVersion < 40) {
      try { await db.execute('ALTER TABLE product_master ADD COLUMN preferred_wholesale TEXT'); } catch (_) {}
    }
    if (oldVersion < 41) {
      try { await db.execute('ALTER TABLE product_master ADD COLUMN lead_time INTEGER DEFAULT 2'); } catch (_) {}
    }
    try { await db.execute('ALTER TABLE product_master ADD COLUMN alias TEXT DEFAULT ""'); } catch (_) {}
    if (oldVersion < 42) {
      try { await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_mapping_unique ON ProductMappings(wholesaler_name, external_name, external_code)'); } catch (_) {}
    }
    if (oldVersion < 43) {
      try { await db.execute('ALTER TABLE purchase_items ADD COLUMN product_id TEXT'); } catch (_) {}
    }
    if (oldVersion < 44) {
      try {
        await db.execute('ALTER TABLE purchase_entries ADD COLUMN done_by TEXT');
        await db.execute('ALTER TABLE purchase_entries ADD COLUMN inv_total REAL DEFAULT 0.0');
      } catch (_) {}
    }
    if (oldVersion < 45) {
      try { await db.execute('ALTER TABLE purchase_entries ADD COLUMN remarks TEXT'); } catch (_) {}
    }
    if (oldVersion < 46) {
      try {
        await db.execute('ALTER TABLE sales_invoices ADD COLUMN secondary_acc TEXT');
        await db.execute('ALTER TABLE sales_invoices ADD COLUMN secondary_amt REAL DEFAULT 0.0');
      } catch (_) {}
    }
    if (oldVersion < 47) {
      try {
        await db.execute('CREATE TABLE IF NOT EXISTS system_security (setting_key TEXT PRIMARY KEY, setting_value TEXT, is_enabled INTEGER DEFAULT 0)');
        await db.execute('CREATE TABLE IF NOT EXISTS system_audit_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, action_type TEXT, description TEXT, user_role TEXT DEFAULT \'Admin\', user_id TEXT DEFAULT \'Admin\')');
        await db.execute('CREATE TABLE IF NOT EXISTS edit_history_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, original_entry_no TEXT, edit_timestamp TEXT, previous_grand_total REAL, previous_items_json TEXT, reason_for_edit TEXT)');
      } catch (_) {}
    }
    if (oldVersion < 48) {
      try {
        await db.execute('CREATE TABLE IF NOT EXISTS suppliers (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, mobile TEXT, address TEXT, email TEXT, gst_in TEXT, dl_number TEXT, current_balance REAL DEFAULT 0.0, is_active INTEGER DEFAULT 1)');
        await db.execute('CREATE TABLE IF NOT EXISTS patients (id TEXT PRIMARY KEY, name TEXT NOT NULL, mobile TEXT, address TEXT, email TEXT, current_balance REAL DEFAULT 0.0, is_active INTEGER DEFAULT 1)');
        await db.execute('CREATE TABLE IF NOT EXISTS doctors (id TEXT PRIMARY KEY, name TEXT NOT NULL, mobile TEXT, specialization TEXT, reg_no TEXT, is_active INTEGER DEFAULT 1)');
        try { await db.execute('ALTER TABLE patients ADD COLUMN loyalty_points INTEGER DEFAULT 0'); } catch (_) {}
      } catch (_) {}
    }
    if (oldVersion < 50) {
      try { await db.execute('ALTER TABLE stock_batches ADD COLUMN supplier_name TEXT'); } catch (_) {}
    }
    if (oldVersion < 51) {
      try { await db.execute('ALTER TABLE generics ADD COLUMN use TEXT'); } catch (_) {}
    }
    if (oldVersion < 52) {
      try {
        var srCols = await db.rawQuery('PRAGMA table_info(sales_return_invoices)');
        if (!srCols.any((c) => c['name'] == 'customer_acc')) await db.execute('ALTER TABLE sales_return_invoices ADD COLUMN customer_acc TEXT');
        if (!srCols.any((c) => c['name'] == 'doctor')) await db.execute('ALTER TABLE sales_return_invoices ADD COLUMN doctor TEXT DEFAULT "Unknown"');
        if (!srCols.any((c) => c['name'] == 'original_invoice_no')) await db.execute('ALTER TABLE sales_return_invoices ADD COLUMN original_invoice_no TEXT');
        if (!srCols.any((c) => c['name'] == 'is_deleted')) await db.execute('ALTER TABLE sales_return_invoices ADD COLUMN is_deleted INTEGER DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 53) {
      try {
        await db.execute('ALTER TABLE purchase_entries ADD COLUMN sub_total REAL DEFAULT 0.0');
        await db.execute('ALTER TABLE purchase_entries ADD COLUMN discount REAL DEFAULT 0.0');
        await db.execute('ALTER TABLE purchase_entries ADD COLUMN other_charge REAL DEFAULT 0.0');
        await db.execute('ALTER TABLE purchase_entries ADD COLUMN round_off REAL DEFAULT 0.0');
      } catch (_) {}
    }
    if (oldVersion < 55) {
      try {
        final tables = [
          'sales_invoices', 'purchase_entries', 'sales_return_invoices',
          'purchase_return_entries', 'stock_adjustments', 'stock_write_offs', 'prescriptions'
        ];
        for (var table in tables) {
          try { await db.execute('ALTER TABLE $table ADD COLUMN financial_year TEXT'); } catch (_) {}
        }
      } catch (_) {}
    }
    if (oldVersion < 59) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS patient_payments (
            id TEXT PRIMARY KEY,
            patient_name TEXT,
            date TEXT,
            amount REAL,
            invoice_no TEXT,
            payment_method TEXT,
            remarks TEXT
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 60) {
      try {
        await db.execute('ALTER TABLE purchase_entries ADD COLUMN is_deleted INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE purchase_return_entries ADD COLUMN is_deleted INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE stock_adjustments ADD COLUMN is_deleted INTEGER DEFAULT 0');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS voucher_sequences (
            voucher_type TEXT,
            financial_year TEXT,
            last_sequence INTEGER DEFAULT 0,
            PRIMARY KEY (voucher_type, financial_year)
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 61) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS monthly_closing_balances (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            closing_month_year TEXT NOT NULL, 
            product_id TEXT NOT NULL,
            batch_number TEXT NOT NULL,
            closing_stock INTEGER NOT NULL,
            landing_cost REAL NOT NULL,
            mrp REAL NOT NULL,
            UNIQUE(closing_month_year, product_id, batch_number)
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 69) {
      try {
        await db.execute("ALTER TABLE sales_invoices ADD COLUMN sales_return_amt REAL DEFAULT 0.0");
      } catch (_) {}
    }
    if (oldVersion < 70) {
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_date_fy ON sales_invoices(date, financial_year, is_deleted);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pur_date_fy ON purchase_entries(date, financial_year, is_deleted);');
      } catch (_) {}
    }
    if (oldVersion < 71) {
      try {
        await db.execute('CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT, balance REAL DEFAULT 0.0, is_active INTEGER DEFAULT 1)');

        await db.update('accounts', {'name': 'UPI'}, where: 'name = ?', whereArgs: ['GPAY']);

        final List<Map<String, String>> initialAccounts = [
          {'id': 'ACC_CASH', 'name': 'CASH', 'color': '0xFF4CAF50'},
          {'id': 'ACC_UPI', 'name': 'UPI', 'color': '0xFF2196F3'},
          {'id': 'ACC_NOT_RECEIVED', 'name': 'NOT RECEIVED', 'color': '0xFFEF5350'},
          {'id': 'ACC_PREVIOUS_DAY', 'name': 'PREVIOUS DAY', 'color': '0xFFFBC02D'},
        ];

        for (var acc in initialAccounts) {
          await db.insert('accounts', {
            'id': acc['id'],
            'name': acc['name'],
            'type': 'General',
            'balance': 0.0,
            'is_active': 1,
            'color': acc['color']
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      } catch (_) {}
    }
    if (oldVersion < 72) {
      try {
        var cols = await db.rawQuery('PRAGMA table_info(accounts)');
        if (!cols.any((c) => c['name'] == 'color')) {
          await db.execute('ALTER TABLE accounts ADD COLUMN color TEXT DEFAULT "0xFF94A3B8"');
        }
        await db.update('accounts', {'color': '0xFF4CAF50'}, where: 'name = ?', whereArgs: ['CASH']);
        await db.update('accounts', {'color': '0xFF2196F3'}, where: 'name = ?', whereArgs: ['UPI']);
        await db.update('accounts', {'color': '0xFFEF5350'}, where: 'name = ?', whereArgs: ['NOT RECEIVED']);
        await db.update('accounts', {'color': '0xFFFBC02D'}, where: 'name = ?', whereArgs: ['PREVIOUS DAY']);
      } catch (_) {}
    }
    if (oldVersion < 73) {
      try {
        var cols = await db.rawQuery('PRAGMA table_info(edit_history_logs)');
        if (!cols.any((c) => c['name'] == 'new_items_json')) {
          await db.execute('ALTER TABLE edit_history_logs ADD COLUMN new_items_json TEXT');
        }
      } catch (_) {}
    }
    if (oldVersion < 74) {
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pm_name_nocase ON product_master(name COLLATE NOCASE);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pm_generic_nocase ON product_master(generic_name COLLATE NOCASE);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pm_hsn ON product_master(hsn_code);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sb_prod_stock ON stock_batches(product_id, current_stock);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sb_batch_nocase ON stock_batches(batch_number COLLATE NOCASE);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_items_inv_prod ON sales_items(invoice_no, product_id);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_items_pname_nocase ON sales_items(product_name COLLATE NOCASE);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pur_items_entry_prod ON purchase_items(entry_no, product_id);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pur_items_pname_nocase ON purchase_items(product_name COLLATE NOCASE);');
      } catch (_) {}
    }
    if (oldVersion < 75) {
      try {
        var saleCols = await db.rawQuery('PRAGMA table_info(sales_invoices)');
        if (!saleCols.any((c) => c['name'] == 'order_type')) {
          await db.execute("ALTER TABLE sales_invoices ADD COLUMN order_type INTEGER DEFAULT 0");
        }
        if (!saleCols.any((c) => c['name'] == 'sales_return_amt')) {
          await db.execute("ALTER TABLE sales_invoices ADD COLUMN sales_return_amt REAL DEFAULT 0.0");
        }
        if (!saleCols.any((c) => c['name'] == 'financial_year')) {
          await db.execute("ALTER TABLE sales_invoices ADD COLUMN financial_year TEXT");
        }
        if (!saleCols.any((c) => c['name'] == 'secondary_acc')) {
          await db.execute("ALTER TABLE sales_invoices ADD COLUMN secondary_acc TEXT");
        }
        if (!saleCols.any((c) => c['name'] == 'secondary_amt')) {
          await db.execute("ALTER TABLE sales_invoices ADD COLUMN secondary_amt REAL DEFAULT 0.0");
        }
        if (!saleCols.any((c) => c['name'] == 'is_deleted')) {
          await db.execute("ALTER TABLE sales_invoices ADD COLUMN is_deleted INTEGER DEFAULT 0");
        }
      } catch (_) {}
    }
    if (oldVersion < 76) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS staff (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT,
            role TEXT,
            code TEXT,
            is_active INTEGER DEFAULT 1
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 78) {
      try {
        var purCols = await db.rawQuery('PRAGMA table_info(purchase_entries)');
        if (!purCols.any((c) => c['name'] == 'tax_type')) {
          await db.execute("ALTER TABLE purchase_entries ADD COLUMN tax_type TEXT DEFAULT 'Gst'");
        }
      } catch (_) {}
    }
    if (oldVersion < 79) {
      try {
        final tablesToMigrate = [
          'product_master', 'stock_batches', 'sales_invoices', 'purchase_entries',
          'sales_return_invoices', 'purchase_return_entries', 'patients', 'suppliers',
          'doctors', 'categories', 'manufacturers', 'racks', 'generics', 'accounts',
          'staff', 'prescriptions', 'supplier_payments', 'patient_payments',
          'supplier_credit_notes', 'stock_adjustments', 'stock_write_offs'
        ];
        for (var tName in tablesToMigrate) {
          try {
            var cols = await db.rawQuery('PRAGMA table_info($tName)');
            if (!cols.any((c) => c['name'] == 'is_synced')) {
              await db.execute('ALTER TABLE $tName ADD COLUMN is_synced INTEGER DEFAULT 0');
            }
            if (!cols.any((c) => c['name'] == 'updated_at')) {
              await db.execute('ALTER TABLE $tName ADD COLUMN updated_at TEXT');
            }
          } catch (_) {}
        }
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pm_is_synced ON product_master(is_synced);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sb_is_synced ON stock_batches(is_synced);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_is_synced ON sales_invoices(is_synced);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pur_is_synced ON purchase_entries(is_synced);');
      } catch (_) {}
    }
    if (oldVersion < 80) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS pending_deletions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            entry_no TEXT NOT NULL,
            deleted_at TEXT NOT NULL,
            is_synced INTEGER DEFAULT 0,
            UNIQUE(table_name, entry_no)
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_del_synced ON pending_deletions(is_synced);');
      } catch (_) {}
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT NOT NULL, is_active INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE racks (id TEXT PRIMARY KEY, name TEXT NOT NULL, is_active INTEGER DEFAULT 1, status_date TEXT)');
    await db.execute('CREATE TABLE manufacturers (id TEXT PRIMARY KEY, name TEXT NOT NULL, is_active INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE generics (id TEXT PRIMARY KEY, name TEXT NOT NULL, use TEXT, is_active INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT, balance REAL DEFAULT 0.0, is_active INTEGER DEFAULT 1, color TEXT)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        role TEXT,
        code TEXT,
        is_active INTEGER DEFAULT 1
      )
    ''');

    final List<Map<String, String>> initialAccounts = [
      {'id': 'ACC_CASH', 'name': 'CASH', 'color': '0xFF4CAF50'},
      {'id': 'ACC_UPI', 'name': 'UPI', 'color': '0xFF2196F3'},
      {'id': 'ACC_NOT_RECEIVED', 'name': 'NOT RECEIVED', 'color': '0xFFEF5350'},
      {'id': 'ACC_PREVIOUS_DAY', 'name': 'PREVIOUS DAY', 'color': '0xFFFBC02D'},
    ];

    for (var acc in initialAccounts) {
      await db.insert('accounts', {
        'id': acc['id'],
        'name': acc['name'],
        'type': 'General',
        'balance': 0.0,
        'is_active': 1,
        'color': acc['color']
      });
    }

    await db.execute('''
      CREATE TABLE product_master (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        generic_name TEXT,
        manufacturer_id TEXT,
        category_id TEXT,
        sub_category_id TEXT,
        rack_id TEXT,
        hsn_code TEXT,
        gst_percent REAL DEFAULT 12.0,
        s_disc_percent REAL DEFAULT 0.0,
        schedule TEXT DEFAULT 'H',
        reorder_level INTEGER DEFAULT 10,
        max_level INTEGER DEFAULT 100,
        unit TEXT DEFAULT 'Strip',
        packing INTEGER DEFAULT 10,
        mrp REAL DEFAULT 0.0,
        purchase_rate REAL DEFAULT 0.0,
        sale_rate REAL DEFAULT 0.0,
        patent TEXT,
        barcode TEXT,
        is_controlled INTEGER DEFAULT 0,
        is_banned INTEGER DEFAULT 0,
        is_nrx INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        is_disc_locked INTEGER DEFAULT 0,
        preferred_wholesale TEXT,
        lead_time INTEGER DEFAULT 2,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_batches (
        product_id TEXT,
        batch_number TEXT,
        expiry_date TEXT,
        mfg_date TEXT,
        current_stock INTEGER DEFAULT 0,
        purchase_rate REAL DEFAULT 0.0,
        landing_cost REAL DEFAULT 0.0,
        mrp REAL DEFAULT 0.0,
        sale_rate REAL DEFAULT 0.0,
        s_disc_percent REAL DEFAULT 0.0,
        gst_percent REAL DEFAULT 12.0,
        rack TEXT,
        supplier_name TEXT,
        packing INTEGER DEFAULT 1,
        is_active INTEGER DEFAULT 1,
        financial_year TEXT,
        PRIMARY KEY (product_id, batch_number, expiry_date, purchase_rate, landing_cost, mrp, sale_rate, packing, supplier_name, gst_percent),
        FOREIGN KEY (product_id) REFERENCES product_master (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE batch_master (
        batch_id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        batch_number TEXT NOT NULL,
        expiry_date TEXT NOT NULL,
        mfg_date TEXT,
        supplier_id TEXT,
        supplier_name TEXT,
        packing INTEGER DEFAULT 1,
        purchase_rate REAL DEFAULT 0.0,
        landing_cost REAL DEFAULT 0.0,
        mrp REAL DEFAULT 0.0,
        sale_rate REAL DEFAULT 0.0,
        gst_percent REAL DEFAULT 12.0,
        rack TEXT,
        created_at TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        FOREIGN KEY (product_id) REFERENCES product_master (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_ledger (
        ledger_id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        batch_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        voucher_type TEXT NOT NULL,
        voucher_no TEXT NOT NULL,
        qty_in INTEGER DEFAULT 0,
        qty_out INTEGER DEFAULT 0,
        purchase_rate REAL DEFAULT 0.0,
        mrp REAL DEFAULT 0.0,
        supplier_name TEXT,
        remarks TEXT,
        user_id TEXT DEFAULT 'Admin',
        financial_year TEXT,
        FOREIGN KEY (batch_id) REFERENCES batch_master (batch_id),
        FOREIGN KEY (product_id) REFERENCES product_master (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE sales_invoices (
        entry_no TEXT PRIMARY KEY,
        invoice_no TEXT,
        date TEXT NOT NULL,
        customer_acc TEXT,
        customer_name TEXT,
        patient TEXT,
        mobile TEXT,
        doctor TEXT,
        doctor_reg_no TEXT,
        sub_total REAL DEFAULT 0.0,
        total_amount REAL,
        discount_percent REAL DEFAULT 0.0,
        discount REAL,
        additional_discount REAL DEFAULT 0.0,
        other_charge REAL DEFAULT 0.0,
        tax REAL,
        round_off REAL DEFAULT 0.0,
        grand_total REAL,
        rcvd_amt REAL DEFAULT 0.0,
        payment_mode TEXT,
        payment_remarks TEXT,
        secondary_acc TEXT,
        secondary_amt REAL DEFAULT 0.0,
        is_deleted INTEGER DEFAULT 0,
        is_paid INTEGER DEFAULT 1,
        is_imported INTEGER DEFAULT 0,
        days INTEGER DEFAULT 0,
        tax_type TEXT DEFAULT 'Non Gst',
        special_order_json TEXT,
        agent TEXT DEFAULT 'Admin',
        expecting_date TEXT,
        special_customer_name TEXT,
        special_customer_phone TEXT,
        financial_year TEXT,
        sales_return_amt REAL DEFAULT 0.0,
        order_type INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE sales_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_no TEXT,
        product_id TEXT,
        product_name TEXT,
        extra TEXT,
        batch_number TEXT,
        expiry_date TEXT,
        qty INTEGER,
        quantity INTEGER,
        packin INTEGER,
        packing INTEGER,
        mrp REAL,
        purchase_rate REAL DEFAULT 0.0,
        landing_cost REAL DEFAULT 0.0,
        taxable_sp REAL,
        s_rate REAL,
        sale_rate REAL,
        disc_percent REAL,
        disc_amt REAL,
        gst_percent REAL,
        tax_percent REAL,
        gst_amt REAL,
        cgst_amt REAL DEFAULT 0.0,
        sgst_amt REAL DEFAULT 0.0,
        igst_amt REAL DEFAULT 0.0,
        total REAL,
        profit REAL,
        supplier_name TEXT,
        rack TEXT,
        terminal_id TEXT DEFAULT 'POS-01',
        FOREIGN KEY (invoice_no) REFERENCES sales_invoices (entry_no)
      )
    ''');

    await db.execute('''
      CREATE TABLE purchase_entries (
        entry_no TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        supplier_name TEXT,
        sup_inv_no TEXT,
        sup_inv_date TEXT,
        done_by TEXT,
        inv_total REAL DEFAULT 0.0,
        remarks TEXT,
        sub_total REAL DEFAULT 0.0,
        discount REAL DEFAULT 0.0,
        other_charge REAL DEFAULT 0.0,
        round_off REAL DEFAULT 0.0,
        grand_total REAL,
        payment_status INTEGER DEFAULT 0,
        payment_mode TEXT,
        payment_remarks TEXT,
        payment_date TEXT,
        paid_amount REAL DEFAULT 0.0,
        days INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        financial_year TEXT,
        tax_type TEXT DEFAULT 'Gst'
      )
    ''');

    await db.execute('''
      CREATE TABLE purchase_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        product_id TEXT,
        product_name TEXT,
        extra TEXT,
        batch TEXT,
        expiry TEXT,
        packin INTEGER,
        qty INTEGER,
        f_qty INTEGER,
        mrp REAL,
        p_rate REAL,
        gross REAL,
        disc_percent REAL,
        disc_amt REAL,
        net REAL,
        gst_percent REAL,
        gst_amt REAL,
        total REAL,
        rack TEXT,
        hsn_code TEXT,
        s_disc_percent REAL DEFAULT 0.0,
        s_rate REAL DEFAULT 0.0,
        l_cost REAL DEFAULT 0.0,
        terminal_id TEXT DEFAULT 'POS-01',
        FOREIGN KEY (entry_no) REFERENCES purchase_entries (entry_no)
      )
    ''');

    await db.execute('CREATE TABLE suppliers (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, mobile TEXT, address TEXT, email TEXT, gst_in TEXT, dl_number TEXT, current_balance REAL DEFAULT 0.0, is_active INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE patients (id TEXT PRIMARY KEY, name TEXT NOT NULL, mobile TEXT, address TEXT, email TEXT, current_balance REAL DEFAULT 0.0, is_active INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE doctors (id TEXT PRIMARY KEY, name TEXT NOT NULL, mobile TEXT, specialization TEXT, reg_no TEXT, is_active INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE sales_return_invoices (entry_no TEXT PRIMARY KEY, date TEXT NOT NULL, customer_acc TEXT, patient TEXT, doctor TEXT, sub_total REAL DEFAULT 0.0, discount REAL DEFAULT 0.0, tax REAL DEFAULT 0.0, round_off REAL DEFAULT 0.0, grand_total REAL, narration TEXT, gst_mode INTEGER DEFAULT 1, original_invoice_no TEXT, is_deleted INTEGER DEFAULT 0, is_imported INTEGER DEFAULT 0, financial_year TEXT)');
    await db.execute('CREATE TABLE sales_return_items (id INTEGER PRIMARY KEY AUTOINCREMENT, return_no TEXT, product_id TEXT, product_name TEXT, batch_number TEXT, expiry_date TEXT, quantity INTEGER, mrp REAL, sale_rate REAL, disc_percent REAL DEFAULT 0.0, disc_amt REAL DEFAULT 0.0, hsn_code TEXT, total REAL, purchase_rate REAL DEFAULT 0.0, landing_cost REAL DEFAULT 0.0, supplier_name TEXT, packing INTEGER DEFAULT 1, gst_percent REAL DEFAULT 12.0, FOREIGN KEY (return_no) REFERENCES sales_return_invoices (entry_no))');
    await db.execute('CREATE TABLE purchase_return_entries (entry_no TEXT PRIMARY KEY, date TEXT NOT NULL, supplier_name TEXT, original_purchase_no TEXT, done_by TEXT, grand_total REAL, gst_mode INTEGER DEFAULT 1, is_deleted INTEGER DEFAULT 0, is_imported INTEGER DEFAULT 0, financial_year TEXT)');
    await db.execute('CREATE TABLE purchase_return_items (id INTEGER PRIMARY KEY AUTOINCREMENT, entry_no TEXT, product_name TEXT, batch TEXT, expiry TEXT, qty INTEGER, loose_qty INTEGER DEFAULT 0, f_qty INTEGER, unit TEXT, packin INTEGER, mrp REAL, p_rate REAL, s_rate REAL, disc_percent REAL, gst_percent REAL, total REAL, reason TEXT, supplier TEXT, hsn_code TEXT, sup_inv_no TEXT, FOREIGN KEY (entry_no) REFERENCES purchase_return_entries (entry_no))');
    await db.execute('CREATE TABLE prescriptions (id TEXT PRIMARY KEY, prescription_no INTEGER DEFAULT 0, patient_name TEXT, doctor_name TEXT, disease_name TEXT, mobile TEXT, days INTEGER, date TEXT, sale_entry_no TEXT, is_active INTEGER DEFAULT 1, is_imported INTEGER DEFAULT 0, financial_year TEXT)');
    await db.execute('CREATE TABLE prescription_items (id INTEGER PRIMARY KEY AUTOINCREMENT, prescription_id TEXT, name TEXT, qty REAL, FOREIGN KEY (prescription_id) REFERENCES prescriptions (id))');
    await db.execute('CREATE TABLE supplier_payments (id TEXT PRIMARY KEY, supplier_name TEXT, date TEXT, amount REAL, invoice_no TEXT, payment_method TEXT, remarks TEXT)');
    await db.execute('CREATE TABLE patient_payments (id TEXT PRIMARY KEY, patient_name TEXT, date TEXT, amount REAL, invoice_no TEXT, payment_method TEXT, remarks TEXT)');
    await db.execute('CREATE TABLE supplier_credit_notes (id TEXT PRIMARY KEY, supplier_name TEXT, date TEXT, amount REAL, invoice_no TEXT, remarks TEXT)');
    await db.execute('CREATE TABLE stock_adjustments (entry_no TEXT PRIMARY KEY, date TEXT NOT NULL, done_by TEXT, reason TEXT, grand_total REAL DEFAULT 0.0, is_deleted INTEGER DEFAULT 0, financial_year TEXT)');
    await db.execute('CREATE TABLE stock_adjustment_items (id INTEGER PRIMARY KEY AUTOINCREMENT, adjustment_no TEXT, product_id TEXT, batch_number TEXT, qty INTEGER, purchase_rate REAL, total REAL, FOREIGN KEY (adjustment_no) REFERENCES stock_adjustments (entry_no))');
    await db.execute('CREATE TABLE stock_write_offs (id TEXT PRIMARY KEY, date TEXT NOT NULL, product_id TEXT, batch_number TEXT, quantity INTEGER, reason TEXT, loss_value REAL, financial_year TEXT, FOREIGN KEY (product_id) REFERENCES product_master (id))');
    await db.execute('CREATE TABLE ProductMappings(id INTEGER PRIMARY KEY AUTOINCREMENT, wholesaler_name TEXT, external_code TEXT, external_name TEXT, internal_name TEXT, product_id TEXT)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_mapping_unique ON ProductMappings(wholesaler_name, external_name, external_code)');
    await db.execute('CREATE TABLE system_security (setting_key TEXT PRIMARY KEY, setting_value TEXT, is_enabled INTEGER DEFAULT 0)');
    await db.execute('CREATE TABLE system_audit_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, action_type TEXT, description TEXT, user_role TEXT DEFAULT \'Admin\', user_id TEXT DEFAULT \'Admin\')');
    await db.execute('CREATE TABLE edit_history_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, original_entry_no TEXT, edit_timestamp TEXT, previous_grand_total REAL, previous_items_json TEXT, new_items_json TEXT, reason_for_edit TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS voucher_sequences (voucher_type TEXT, financial_year TEXT, last_sequence INTEGER DEFAULT 0, PRIMARY KEY (voucher_type, financial_year))');
    await db.execute('CREATE TABLE IF NOT EXISTS monthly_closing_balances (id INTEGER PRIMARY KEY AUTOINCREMENT, closing_month_year TEXT NOT NULL, product_id TEXT NOT NULL, batch_number TEXT NOT NULL, closing_stock INTEGER NOT NULL, landing_cost REAL NOT NULL, mrp REAL NOT NULL, UNIQUE(closing_month_year, product_id, batch_number))');
    await db.execute('CREATE TABLE IF NOT EXISTS rack_history (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id TEXT, product_name TEXT, old_rack TEXT, new_rack TEXT, change_date TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS stock_enquiries (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id TEXT, product_name TEXT NOT NULL, requested_qty INTEGER DEFAULT 1, enquiry_date TEXT NOT NULL, agent TEXT DEFAULT "", customer_name TEXT DEFAULT "")');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_deletions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        entry_no TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0,
        UNIQUE(table_name, entry_no)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_del_synced ON pending_deletions(is_synced);');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_deletions_queue (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_del_synced ON sync_deletions_queue(is_synced);');

    // Performance Indexes
    await db.execute('CREATE INDEX idx_product_name ON product_master(name)');
    await db.execute('CREATE INDEX idx_product_generic ON product_master(generic_name)');
    await db.execute('CREATE INDEX idx_pm_name_nocase ON product_master(name COLLATE NOCASE)');
    await db.execute('CREATE INDEX idx_pm_generic_nocase ON product_master(generic_name COLLATE NOCASE)');
    await db.execute('CREATE INDEX idx_batch_expiry ON stock_batches(expiry_date)');
    await db.execute('CREATE INDEX idx_sales_items_invoice ON sales_items(invoice_no)');
    await db.execute('CREATE INDEX idx_purchase_items_entry ON purchase_items(entry_no)');
    await db.execute('CREATE INDEX idx_sales_patient ON sales_invoices(patient)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_enquiries_date ON stock_enquiries(enquiry_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_enquiries_prod ON stock_enquiries(product_name)');
    await db.execute('CREATE INDEX idx_purchase_supplier ON purchase_entries(supplier_name)');
    await db.execute('CREATE INDEX idx_sales_date_fy ON sales_invoices(date, financial_year, is_deleted)');
    await db.execute('CREATE INDEX idx_pur_date_fy ON purchase_entries(date, financial_year, is_deleted)');
    await db.execute('CREATE INDEX idx_monthly_close ON monthly_closing_balances(closing_month_year)');
  }

  Future<void> _migrateLegacyBatchesToBatchMaster(Database db) async {
    try {
      final existingLegacy = await db.rawQuery('SELECT * FROM stock_batches');
      if (existingLegacy.isEmpty) return;

      int index = 0;
      for (var row in existingLegacy) {
        String productId = row['product_id']?.toString() ?? '';
        String batchNumber = row['batch_number']?.toString() ?? '';
        String expiryDate = row['expiry_date']?.toString() ?? '';
        double purchaseRate = (row['purchase_rate'] as num?)?.toDouble() ?? 0.0;
        double mrp = (row['mrp'] as num?)?.toDouble() ?? 0.0;
        int currentStock = (row['current_stock'] as num?)?.toInt() ?? 0;

        if (productId.isEmpty || batchNumber.isEmpty) continue;

        final check = await db.rawQuery('''
          SELECT batch_id FROM batch_master 
          WHERE product_id = ? AND LOWER(TRIM(batch_number)) = LOWER(TRIM(?)) AND expiry_date = ?
          LIMIT 1
        ''', [productId, batchNumber, expiryDate]);

        String batchId;
        if (check.isNotEmpty) {
          batchId = check.first['batch_id']?.toString() ?? '';
        } else {
          batchId = "BAT_${DateTime.now().microsecondsSinceEpoch}_${index++}";
          await db.insert('batch_master', {
            'batch_id': batchId,
            'product_id': productId,
            'batch_number': batchNumber.trim(),
            'expiry_date': expiryDate,
            'mfg_date': row['mfg_date']?.toString() ?? '',
            'supplier_name': row['supplier_name']?.toString() ?? '',
            'packing': (row['packing'] as num?)?.toInt() ?? 1,
            'purchase_rate': purchaseRate,
            'landing_cost': (row['landing_cost'] as num?)?.toDouble() ?? purchaseRate,
            'mrp': mrp,
            'sale_rate': (row['sale_rate'] as num?)?.toDouble() ?? mrp,
            'gst_percent': (row['gst_percent'] as num?)?.toDouble() ?? 12.0,
            'rack': row['rack']?.toString() ?? '',
            'created_at': DateTime.now().toIso8601String(),
            'is_active': (row['is_active'] as num?)?.toInt() ?? 1,
          });
        }

        if (batchId.isNotEmpty && currentStock > 0) {
          final ledgerCheck = await db.rawQuery(
            'SELECT ledger_id FROM stock_ledger WHERE batch_id = ? LIMIT 1',
            [batchId],
          );
          if (ledgerCheck.isEmpty) {
            await db.insert('stock_ledger', {
              'timestamp': DateTime.now().toIso8601String(),
              'batch_id': batchId,
              'product_id': productId,
              'voucher_type': 'OPENING_STOCK',
              'voucher_no': 'MIGRATION_INIT',
              'qty_in': currentStock,
              'qty_out': 0,
              'purchase_rate': purchaseRate,
              'mrp': mrp,
              'supplier_name': row['supplier_name']?.toString() ?? '',
              'remarks': 'Initial Legacy Migration',
              'user_id': 'System',
              'financial_year': row['financial_year']?.toString() ?? '',
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Legacy batch migration note: $e");
    }
  }

  Future<void> close() async {
    final db = await database;
    try {
      await db.execute('PRAGMA wal_checkpoint(PASSIVE);');
    } catch (_) {}
    db.close();
  }

  Future<String> createLocalBackup() async {
    final db = await database;
    try {
      // PASSIVE checkpoints the WAL log without blocking active transactions
      await db.execute('PRAGMA wal_checkpoint(PASSIVE)');
    } catch (e) {
      debugPrint("WAL Checkpoint Error: $e");
    }

    final dbPath = await getDatabasesPath();
    final sourcePath = join(dbPath, 'pharmacy.db');

    final backupDir = Directory(join(dbPath, 'backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final now = DateTime.now();
    final timestamp = DateFormat('yyyy_MM_dd_HHmmss').format(now);
    final backupFileName = 'pharmacy_backup_$timestamp.db';
    final targetPath = join(backupDir.path, backupFileName);

    final sourceFile = File(sourcePath);
    if (await sourceFile.exists()) {
      final targetFile = File(targetPath);
      await sourceFile.openRead().pipe(targetFile.openWrite());
      await cleanupOldBackups(keepDays: 30);
      return targetPath;
    } else {
      throw "Source database file not found at $sourcePath";
    }
  }

  Future<String?> performAutoBackupIfNeeded({bool forceOnExit = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final lastBackupStr = prefs.getString('last_auto_backup_date') ?? '';

      if (forceOnExit || lastBackupStr != todayStr) {
        final path = await createLocalBackup();
        await prefs.setString('last_auto_backup_date', todayStr);
        debugPrint("Automated Backup Succeeded ($path)");
        return path;
      }
    } catch (e) {
      debugPrint("Automated Backup Failed: $e");
    }
    return null;
  }

  Future<void> cleanupOldBackups({int? keepDays}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final effectiveDays = keepDays ?? (prefs.getInt('backup_retention_days') ?? 30);
      if (effectiveDays <= 0) return; // 0 means Keep All / Unlimited

      final dbPath = await getDatabasesPath();
      final backupDir = Directory(join(dbPath, 'backups'));
      if (await backupDir.exists()) {
        final cutoff = DateTime.now().subtract(Duration(days: effectiveDays));
        final List<FileSystemEntity> files = await backupDir.list().toList();

        for (var entity in files) {
          if (entity is File && entity.path.endsWith('.db')) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
              debugPrint("Cleaned up old backup: ${entity.path}");
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error cleaning old backups: $e");
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableBackups() async {
    List<Map<String, dynamic>> results = [];
    try {
      final dbPath = await getDatabasesPath();
      final backupDir = Directory(join(dbPath, 'backups'));
      if (await backupDir.exists()) {
        final List<FileSystemEntity> files = await backupDir.list().toList();
        for (var entity in files) {
          if (entity is File && entity.path.endsWith('.db')) {
            final stat = await entity.stat();
            final name = basename(entity.path);
            results.add({
              'path': entity.path,
              'name': name,
              'size': stat.size,
              'date': stat.modified,
              'file': entity,
            });
          }
        }
        results.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
      }
    } catch (e) {
      debugPrint("Error getting backup list: $e");
    }
    return results;
  }

  Future<bool> restoreBackupFile(File backupFile) async {
    try {
      if (!await backupFile.exists()) throw "Backup file does not exist.";

      final dbPath = await getDatabasesPath();
      final targetPath = join(dbPath, 'pharmacy.db');

      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      await backupFile.copy(targetPath);
      _database = await _initDB('pharmacy.db');
      return true;
    } catch (e) {
      debugPrint("Error restoring database: $e");
      rethrow;
    }
  }

  Future<void> mergeDuplicateProducts({
    required String keepProductId,
    required String deleteProductId,
  }) async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        final duplicateBatches = await txn.query(
            'stock_batches',
            where: 'product_id = ?',
            whereArgs: [deleteProductId]
        );

        for (var batch in duplicateBatches) {
          String batchNo = batch['batch_number'].toString();
          int stockToTransfer = (batch['current_stock'] as num?)?.toInt() ?? 0;

          List<Map<String, dynamic>> existing = await txn.query(
              'stock_batches',
              where: 'product_id = ? AND batch_number = ?',
              whereArgs: [keepProductId, batchNo]
          );

          if (existing.isNotEmpty) {
            await txn.rawUpdate(
                'UPDATE stock_batches SET current_stock = current_stock + ? WHERE product_id = ? AND batch_number = ?',
                [stockToTransfer, keepProductId, batchNo]
            );
            await txn.delete(
                'stock_batches',
                where: 'product_id = ? AND batch_number = ?',
                whereArgs: [deleteProductId, batchNo]
            );
          } else {
            await txn.update(
                'stock_batches',
                {'product_id': keepProductId},
                where: 'product_id = ? AND batch_number = ?',
                whereArgs: [deleteProductId, batchNo]
            );
          }
        }

        final tablesToUpdate = [
          'purchase_items',
          'sales_items',
          'sales_return_items',
          'purchase_return_items',
          'stock_adjustment_items',
          'stock_write_offs',
          'ProductMappings',
          'rack_history'
        ];

        for (String table in tablesToUpdate) {
          try {
            await txn.rawUpdate(
                'UPDATE $table SET product_id = ? WHERE product_id = ?',
                [keepProductId, deleteProductId]
            );
          } catch (_) {}
        }

        await txn.delete('product_master', where: 'id = ?', whereArgs: [deleteProductId]);
      });
    } catch (e) {
      debugPrint("Critical Error merging products: $e");
      rethrow;
    }
  }

  /// Deduplicates sales_items, purchase_items, and stock_batches in local SQLite
  Future<void> cleanupDuplicateItems([Database? targetDb]) async {
    try {
      final db = targetDb ?? await database;
      await runWithDbRetry(() async {
        await db.execute('''
          DELETE FROM sales_items 
          WHERE rowid NOT IN (
            SELECT MIN(rowid) 
            FROM sales_items 
            GROUP BY invoice_no, COALESCE(NULLIF(product_id, ''), product_name), COALESCE(NULLIF(batch_number, ''), extra), qty
          )
        ''');
      });
      await runWithDbRetry(() async {
        await db.execute('''
          DELETE FROM purchase_items 
          WHERE rowid NOT IN (
            SELECT MIN(rowid) 
            FROM purchase_items 
            GROUP BY entry_no, COALESCE(NULLIF(product_id, ''), product_name), batch, qty
          )
        ''');
      });
      await runWithDbRetry(() async {
        await db.execute('''
          DELETE FROM stock_batches
          WHERE rowid NOT IN (
            SELECT MIN(rowid)
            FROM stock_batches
            GROUP BY product_id, LOWER(TRIM(batch_number))
          )
        ''');
      });
    } catch (e) {
      debugPrint("cleanupDuplicateItems note: $e");
    }
  }

  Future<T> runWithDbRetry<T>(Future<T> Function() action, {int maxAttempts = 10}) async {
    int attempt = 0;
    while (attempt < maxAttempts) {
      attempt++;
      try {
        return await action();
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('database is locked') || errStr.contains('code 5') || errStr.contains('sqliteexception(5)')) {
          if (attempt >= maxAttempts) rethrow;
          await Future.delayed(Duration(milliseconds: 100 * attempt));
        } else {
          rethrow;
        }
      }
    }
    return await action();
  }

  /// Records a sync conflict resolution event for manager audit logs
  static Future<void> logSyncConflict({
    required String tableName,
    required String recordIdentifier,
    required String fieldName,
    required dynamic localValue,
    required dynamic remoteValue,
  }) async {
    try {
      final db = await DbHelper.instance.database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_conflict_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT,
          record_identifier TEXT,
          field_name TEXT,
          local_value TEXT,
          remote_value TEXT,
          resolved_action TEXT,
          created_at TEXT
        )
      ''');

      await db.insert('sync_conflict_logs', {
        'table_name': tableName,
        'record_identifier': recordIdentifier,
        'field_name': fieldName,
        'local_value': localValue?.toString() ?? '',
        'remote_value': remoteValue?.toString() ?? '',
        'resolved_action': 'REPLACED_WITH_CLOUD_VALUE',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      debugPrint("DbHelper: Sync conflict logged for $tableName ($recordIdentifier -> $fieldName)");
    } catch (e) {
      debugPrint("DbHelper: Error logging sync conflict: $e");
    }
  }

  /// Fetches recent sync conflict log entries for audit UI
  static Future<List<Map<String, dynamic>>> getSyncConflictLogs({int limit = 50}) async {
    try {
      final db = await DbHelper.instance.database;
      final tableCheck = await db.rawQuery("SELECT COUNT(*) as cnt FROM sqlite_master WHERE type='table' AND name='sync_conflict_logs'");
      if ((tableCheck.first['cnt'] as int? ?? 0) == 0) return [];

      return await db.query(
        'sync_conflict_logs',
        orderBy: 'id DESC',
        limit: limit,
      );
    } catch (e) {
      debugPrint("DbHelper: Error fetching sync conflict logs: $e");
      return [];
    }
  }

  /// Runs a database write transaction serialized through a single FIFO queue
  Future<T> runWriteTransaction<T>(Future<T> Function(Transaction txn) action) async {
    return await _writeQueue.enqueue(() async {
      return await runWithDbRetry(() async {
        final db = await database;
        return await db.transaction((txn) async {
          return await action(txn);
        });
      });
    });
  }

  /// Runs a database write query (insert, update, delete) serialized through a single FIFO queue
  Future<T> runWriteQuery<T>(Future<T> Function(Database db) action) async {
    return await _writeQueue.enqueue(() async {
      return await runWithDbRetry(() async {
        final db = await database;
        return await action(db);
      });
    });
  }

  Future<T> executeSerializedTransaction<T>(Future<T> Function(Transaction txn) action) async {
    return runWriteTransaction(action);
  }

  // ==========================================
  // ORDER CONFIRMATION & TRACKING METHODS
  // ==========================================

  Future<void> saveOrderConfirmation(OrderConfirmation order) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'order_confirmations',
        order.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'order_confirmation_items',
        where: 'order_id = ?',
        whereArgs: [order.orderId],
      );

      for (var item in order.items) {
        await txn.insert(
          'order_confirmation_items',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<OrderConfirmation>> fetchOrderConfirmations({
    DateTime? fromDate,
    DateTime? toDate,
    String? statusFilter,
    String? searchQuery,
  }) async {
    final db = await database;
    List<String> whereClauses = [];
    List<dynamic> whereArgs = [];

    if (fromDate != null) {
      whereClauses.add('order_date >= ?');
      whereArgs.add(fromDate.toIso8601String());
    }
    if (toDate != null) {
      whereClauses.add('order_date <= ?');
      whereArgs.add(toDate.toIso8601String());
    }
    if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'ALL') {
      whereClauses.add('status = ?');
      whereArgs.add(statusFilter);
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim().toLowerCase()}%';
      whereClauses.add('(LOWER(order_id) LIKE ? OR LOWER(supplier_name) LIKE ? OR order_id IN (SELECT order_id FROM order_confirmation_items WHERE LOWER(product_name) LIKE ?))');
      whereArgs.addAll([q, q, q]);
    }

    String whereSql = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';

    final rows = await db.rawQuery('''
      SELECT * FROM order_confirmations
      $whereSql
      ORDER BY order_date DESC
    ''', whereArgs);

    if (rows.isEmpty) return [];

    List<String> orderIds = rows.map((r) => r['order_id'] as String).toList();
    final placeholders = List.filled(orderIds.length, '?').join(',');
    final allItemRows = await db.query(
      'order_confirmation_items',
      where: 'order_id IN ($placeholders)',
      whereArgs: orderIds,
    );

    Map<String, List<OrderConfirmationItem>> itemsByOrder = {};
    for (var itemMap in allItemRows) {
      String oId = itemMap['order_id'] as String;
      itemsByOrder.putIfAbsent(oId, () => []).add(OrderConfirmationItem.fromMap(itemMap));
    }

    List<OrderConfirmation> results = [];
    for (var r in rows) {
      String orderId = r['order_id'] as String;
      List<OrderConfirmationItem> items = itemsByOrder[orderId] ?? [];
      results.add(OrderConfirmation.fromMap(r, items: items));
    }
    return results;
  }

  Future<void> updateOrderConfirmationStatus(String orderId, String status, {String? receivedDate}) async {
    final db = await database;
    await db.transaction((txn) async {
      Map<String, dynamic> updateData = {'status': status};
      if (receivedDate != null) {
        updateData['received_date'] = receivedDate;
      }
      await txn.update(
        'order_confirmations',
        updateData,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      if (status == 'RECEIVED') {
        await txn.update(
          'order_confirmation_items',
          {
            'status': 'RECEIVED',
            'received_date': receivedDate ?? DateTime.now().toIso8601String().split('T')[0],
          },
          where: 'order_id = ?',
          whereArgs: [orderId],
        );
      }
    });
  }

  Future<void> updateOrderItemReceivedStatus({
    required int itemId,
    required int receivedQty,
    required String status,
    String? receivedDate,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'order_confirmation_items',
        {
          'received_qty': receivedQty,
          'status': status,
          'received_date': receivedDate ?? DateTime.now().toIso8601String().split('T')[0],
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );

      final itemRows = await txn.rawQuery(
        'SELECT order_id FROM order_confirmation_items WHERE id = ?',
        [itemId],
      );
      if (itemRows.isNotEmpty) {
        String orderId = itemRows.first['order_id'] as String;
        final allItems = await txn.query(
          'order_confirmation_items',
          where: 'order_id = ?',
          whereArgs: [orderId],
        );

        bool allReceived = allItems.every((i) => i['status'] == 'RECEIVED');
        bool anyReceived = allItems.any((i) => i['status'] == 'RECEIVED' || (i['received_qty'] as num? ?? 0) > 0);

        String orderStatus = 'PENDING';
        if (allReceived) {
          orderStatus = 'RECEIVED';
        } else if (anyReceived) {
          orderStatus = 'PARTIAL';
        }

        await txn.update(
          'order_confirmations',
          {'status': orderStatus},
          where: 'order_id = ?',
          whereArgs: [orderId],
        );
      }
    });
  }

  Future<void> deleteOrderConfirmation(String orderId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'order_confirmation_items',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
      await txn.delete(
        'order_confirmations',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
    });
  }

  /// Writes an immutable audit trail entry for FDA and statutory regulatory compliance
  Future<void> logFdaAuditEvent({
    required String action,
    required String description,
    String userRole = "Admin",
    String userId = "Admin",
  }) async {
    try {
      final db = await database;
      await db.insert('system_audit_logs', {
        'timestamp': DateTime.now().toIso8601String(),
        'action_type': action,
        'description': description,
        'user_role': userRole,
        'user_id': userId,
      });
    } catch (e) {
      debugPrint("FDA Audit Log Error: $e");
    }
  }

  /// Fetches loyalty points for a patient by name or phone
  Future<int> getCustomerLoyaltyPoints(String patientName) async {
    try {
      final db = await database;
      final res = await db.query(
        'patients',
        columns: ['loyalty_points'],
        where: 'name LIKE ? OR mobile = ?',
        whereArgs: [patientName, patientName],
      );
      if (res.isNotEmpty) {
        return (res.first['loyalty_points'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      debugPrint("Loyalty points query error: $e");
    }
    return 0;
  }

  /// Updates loyalty points for a patient
  Future<void> updateCustomerLoyaltyPoints(String patientName, int pointsDelta) async {
    try {
      final db = await database;
      await db.rawUpdate('''
        UPDATE patients 
        SET loyalty_points = COALESCE(loyalty_points, 0) + ? 
        WHERE name LIKE ? OR mobile = ?
      ''', [pointsDelta, patientName, patientName]);
    } catch (e) {
      debugPrint("Loyalty points update error: $e");
    }
  }

  // Parked Sales (Bill Park & Recall)
  Future<void> saveParkedBill(String parkKey, String customerName, String dataJson) async {
    final db = await database;
    await db.insert(
      'parked_sales',
      {
        'park_key': parkKey,
        'customer_name': customerName,
        'data_json': dataJson,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getParkedBills() async {
    final db = await database;
    try {
      return await db.query('parked_sales', orderBy: 'created_at DESC');
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteParkedBill(String parkKey) async {
    final db = await database;
    await db.delete('parked_sales', where: 'park_key = ?', whereArgs: [parkKey]);
  }

  /// Issue 5.1: Deducts stock from stock_batches table for a given batch and quantity.
  Future<void> deductBatchStock({
    required dynamic batchId,
    String? productId,
    required num qty,
  }) async {
    final db = await database;
    int remaining = qty.toInt();
    if (remaining <= 0) return;

    await db.transaction((txn) async {
      List<Map<String, dynamic>> matchingRows = [];
      final strBatchId = batchId?.toString().trim() ?? '';
      final strProductId = productId?.trim() ?? '';

      // 1. Try matching by batch_id / batch_number in stock_batches
      if (strBatchId.isNotEmpty) {
        matchingRows = await txn.rawQuery('''
          SELECT rowid, current_stock
          FROM stock_batches
          WHERE (product_id = ? OR ? = '')
            AND (batch_number = ? OR rowid = ?)
            AND current_stock > 0
          ORDER BY rowid ASC
        ''', [strProductId, strProductId, strBatchId, int.tryParse(strBatchId) ?? -1]);

        // 2. Try looking up batch_master if stock_batches search returned nothing
        if (matchingRows.isEmpty) {
          final bm = await txn.query('batch_master', where: 'batch_id = ?', whereArgs: [strBatchId]);
          if (bm.isNotEmpty) {
            final bmProdId = bm.first['product_id']?.toString() ?? strProductId;
            final bmBatchNo = bm.first['batch_number']?.toString() ?? '';
            matchingRows = await txn.rawQuery('''
              SELECT rowid, current_stock
              FROM stock_batches
              WHERE product_id = ? AND batch_number = ? AND current_stock > 0 COLLATE NOCASE
              ORDER BY rowid ASC
            ''', [bmProdId, bmBatchNo]);
          }
        }
      }

      // 3. Fallback: query by productId and batch_number
      if (matchingRows.isEmpty && strProductId.isNotEmpty) {
        matchingRows = await txn.rawQuery('''
          SELECT rowid, current_stock
          FROM stock_batches
          WHERE product_id = ? AND (batch_number = ? OR ? = '') AND current_stock > 0 COLLATE NOCASE
          ORDER BY rowid ASC
        ''', [strProductId, strBatchId, strBatchId]);
      }

      // Deduct from matched batch rows
      for (var bRow in matchingRows) {
        if (remaining <= 0) break;
        int rowid = bRow['rowid'] as int;
        int availableInRow = (bRow['current_stock'] as num).toInt();
        int deduct = (remaining <= availableInRow) ? remaining : availableInRow;

        await txn.rawUpdate(
          'UPDATE stock_batches SET current_stock = current_stock - ? WHERE rowid = ?',
          [deduct, rowid],
        );
        remaining -= deduct;
      }

      // 4. Direct deduction if remaining > 0
      if (remaining > 0 && strProductId.isNotEmpty) {
        await txn.rawUpdate('''
          UPDATE stock_batches
          SET current_stock = MAX(0, current_stock - ?)
          WHERE product_id = ? AND (batch_number = ? OR ? = '')
        ''', [remaining, strProductId, strBatchId, strBatchId]);
      } else if (remaining > 0 && strBatchId.isNotEmpty) {
        await txn.rawUpdate('''
          UPDATE stock_batches
          SET current_stock = MAX(0, current_stock - ?)
          WHERE batch_number = ?
        ''', [remaining, strBatchId]);
      }
    });
  }

  /// Central update method that sets is_synced = 0 and updated_at to UTC ISO timestamp before performing update.
  Future<int> markDirtyAndUpdate(
    String table,
    Map<String, dynamic> values,
    String where,
    List<dynamic> whereArgs, {
    DatabaseExecutor? executor,
  }) async {
    final Map<String, dynamic> mutableValues = Map<String, dynamic>.from(values);
    mutableValues['is_synced'] = 0;
    mutableValues['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final exec = executor ?? await database;
    return await exec.update(table, mutableValues, where: where, whereArgs: whereArgs);
  }

  /// Queues a deletion tombstone record in sync_deletions_queue and pending_deletions.
  Future<void> queueDeletion(
    String table,
    String recordId, {
    DatabaseExecutor? executor,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final exec = executor ?? await database;
    final String delId = "${table}_${recordId}_${DateTime.now().millisecondsSinceEpoch}";
    try {
      await exec.insert(
        'sync_deletions_queue',
        {
          'id': delId,
          'table_name': table,
          'record_id': recordId,
          'deleted_at': nowIso,
          'is_synced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint("Error inserting into sync_deletions_queue: $e");
    }
    try {
      await exec.insert(
        'pending_deletions',
        {
          'table_name': table,
          'entry_no': recordId,
          'deleted_at': nowIso,
          'is_synced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  /// Ensures stock convergence infrastructure tables (stock_outbox, processed_sync_events, stock_ledger extensions) exist.
  Future<void> ensureStockConvergenceTables([DatabaseExecutor? executor]) async {
    final db = executor ?? await database;
    try {
      // 1. Durable Local Outbox Table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_outbox (
          id TEXT PRIMARY KEY,
          idempotency_key TEXT UNIQUE NOT NULL,
          operation_type TEXT NOT NULL,
          reference_no TEXT NOT NULL,
          branch_id TEXT NOT NULL,
          terminal_id TEXT NOT NULL,
          user_id TEXT,
          payload TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          error_message TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          retry_count INTEGER DEFAULT 0,
          last_attempt_at TEXT
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_outbox_status ON stock_outbox(status, created_at);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_outbox_ref ON stock_outbox(operation_type, reference_no);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_outbox_status_retries ON stock_outbox(status, retry_count, created_at ASC);');

      // 2. Processed Sync Events Table (for idempotent event handling across Realtime, LAN, Delta Sync)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS processed_sync_events (
          event_id TEXT PRIMARY KEY,
          source TEXT NOT NULL,
          processed_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_proc_sync_events_time ON processed_sync_events(processed_at);');

      // 3. Stock Ledger Table & Columns
      await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT,
          created_at TEXT,
          batch_id TEXT,
          product_id TEXT,
          voucher_type TEXT,
          voucher_no TEXT,
          qty_in INTEGER DEFAULT 0,
          qty_out INTEGER DEFAULT 0,
          quantity_delta INTEGER DEFAULT 0,
          closing_balance INTEGER DEFAULT 0,
          purchase_rate REAL DEFAULT 0.0,
          mrp REAL DEFAULT 0.0,
          supplier_name TEXT,
          remarks TEXT,
          user_id TEXT,
          financial_year TEXT,
          branch_id TEXT DEFAULT 'MAIN_STORE',
          terminal_id TEXT DEFAULT 'POS-01',
          idempotency_key TEXT
        )
      ''');

      final ledgerCols = await db.rawQuery('PRAGMA table_info(stock_ledger)');
      final colNames = ledgerCols.map((c) => c['name']?.toString()).toSet();
      if (!colNames.contains('batch_number')) {
        await db.execute('ALTER TABLE stock_ledger ADD COLUMN batch_number TEXT');
      }
      if (!colNames.contains('idempotency_key')) {
        await db.execute('ALTER TABLE stock_ledger ADD COLUMN idempotency_key TEXT');
      }
      if (!colNames.contains('branch_id')) {
        await db.execute("ALTER TABLE stock_ledger ADD COLUMN branch_id TEXT DEFAULT 'MAIN_STORE'");
      }
      if (!colNames.contains('terminal_id')) {
        await db.execute("ALTER TABLE stock_ledger ADD COLUMN terminal_id TEXT DEFAULT 'POS-01'");
      }
      if (!colNames.contains('quantity_delta')) {
        await db.execute('ALTER TABLE stock_ledger ADD COLUMN quantity_delta INTEGER DEFAULT 0');
      }
      if (!colNames.contains('closing_balance')) {
        await db.execute('ALTER TABLE stock_ledger ADD COLUMN closing_balance INTEGER DEFAULT 0');
      }
      if (!colNames.contains('created_at')) {
        await db.execute('ALTER TABLE stock_ledger ADD COLUMN created_at TEXT');
      }
      try {
        await db.execute("UPDATE stock_ledger SET created_at = timestamp WHERE (created_at IS NULL OR created_at = '') AND timestamp IS NOT NULL;");
      } catch (_) {}
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sl_idemp ON stock_ledger(idempotency_key);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sl_branch ON stock_ledger(branch_id, product_id);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_ledger_branch_batch ON stock_ledger(branch_id, batch_number, created_at DESC);');
    } catch (e) {
      debugPrint("ensureStockConvergenceTables error: $e");
    }
  }

  /// Checks if a sync/LAN event has already been processed locally
  Future<bool> isEventAlreadyProcessed(String eventId, [DatabaseExecutor? executor]) async {
    final clean = eventId.trim();
    if (clean.isEmpty) return false;
    final db = executor ?? await database;
    try {
      final res = await db.query(
        'processed_sync_events',
        where: 'event_id = ?',
        whereArgs: [clean],
        limit: 1,
      );
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Marks a sync/LAN event as processed in SQLite
  Future<void> markEventProcessed(String eventId, [String source = 'LAN', DatabaseExecutor? executor]) async {
    final clean = eventId.trim();
    if (clean.isEmpty) return;
    final db = executor ?? await database;
    try {
      await db.insert(
        'processed_sync_events',
        {
          'event_id': clean,
          'source': source,
          'processed_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (_) {}
  }

  /// Records an immutable audit ledger movement in local SQLite
  Future<void> recordStockLedgerEntryInTxn(
    DatabaseExecutor txn, {
    required String batchNumber,
    required String productId,
    String? voucherType,
    String? entryType,
    String? voucherNo,
    String? referenceNo,
    required int quantityDelta,
    int qtyIn = 0,
    int qtyOut = 0,
    int closingBalance = 0,
    double purchaseRate = 0.0,
    double mrp = 0.0,
    String supplierName = '',
    String remarks = '',
    String? userId,
    String? branchId,
    String? terminalId,
    String? idempotencyKey,
  }) async {
    final config = ServerConfigService.instance;
    final vType = voucherType ?? entryType ?? 'STOCK_MOVE';
    final vNo = voucherNo ?? referenceNo ?? '';
    await txn.insert('stock_ledger', {
      'timestamp': DateTime.now().toIso8601String(),
      'batch_id': batchNumber,
      'batch_number': batchNumber,
      'product_id': productId,
      'voucher_type': vType,
      'voucher_no': vNo,
      'qty_in': qtyIn > 0 ? qtyIn : (quantityDelta > 0 ? quantityDelta : 0),
      'qty_out': qtyOut > 0 ? qtyOut : (quantityDelta < 0 ? quantityDelta.abs() : 0),
      'quantity_delta': quantityDelta,
      'closing_balance': closingBalance,
      'purchase_rate': purchaseRate,
      'mrp': mrp,
      'supplier_name': supplierName,
      'remarks': remarks,
      'user_id': userId ?? 'Admin',
      'financial_year': '',
      'branch_id': branchId ?? config.storeBranchId,
      'terminal_id': terminalId ?? config.terminalId,
      'idempotency_key': idempotencyKey,
    });
  }
}

class _AsyncWriteQueue {
  Future<void>? _last;

  Future<T> enqueue<T>(Future<T> Function() action) async {
    final previous = _last;
    final completer = Completer<void>();
    _last = completer.future;

    if (previous != null) {
      try {
        await previous.timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    try {
      return await action();
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }
}