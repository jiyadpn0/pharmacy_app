import 'dart:io';
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/erp_models.dart';
import '../utils/app_formatters.dart';

class DbHelper {
  static final DbHelper instance = DbHelper._init();
  static Database? _database;

  DbHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pharmacy.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    final db = await openDatabase(
      path,
      version: 76, // Incremented to 76 for staff management table migration
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
        await db.execute('PRAGMA journal_mode = WAL;');
        await db.execute('PRAGMA synchronous = NORMAL;');
        await db.execute('PRAGMA cache_size = -64000;'); // ~64MB Cache
        await db.execute('PRAGMA temp_store = MEMORY;');
        await db.execute('PRAGMA mmap_size = 536870912;'); // 512MB memory mapping
      },
    );

    await checkAndMigrateColumns(db);
    return db;
  }

  Future<void> checkAndMigrateColumns(Database db) async {
    // Safety check: ensure order_type column always exists on sales_invoices table
    try {
      var saleCols = await db.rawQuery('PRAGMA table_info(sales_invoices)');
      if (!saleCols.any((c) => c['name'] == 'order_type')) {
        await db.execute("ALTER TABLE sales_invoices ADD COLUMN order_type INTEGER DEFAULT 0");
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
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
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pur_items_prod_qty ON purchase_items(product_id, qty);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pur_entries_entry_date ON purchase_entries(entry_no, date, is_deleted);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_batches_name ON stock_batches(product_name);');
        await txn.execute("UPDATE sales_invoices SET date = substr(date, 7, 4) || '-' || substr(date, 4, 2) || '-' || substr(date, 1, 2) || 'T00:00:00.000' WHERE date LIKE '__/__/____%';");
      } catch (_) {}

      // 10. Performance Indexes for 50k+ Product Master & Batch Lookups
      try {
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pm_name_nocase ON product_master(name COLLATE NOCASE);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pm_generic_nocase ON product_master(generic_name COLLATE NOCASE);');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_pm_hsn ON product_master(hsn_code);');
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
      } catch (e) {
        debugPrint("Product name migration note: $e");
      }

      await prefs.setBool('schema_v75_migrated_done', true);
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
        lead_time INTEGER DEFAULT 2
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
        financial_year TEXT
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
        FOREIGN KEY (entry_no) REFERENCES purchase_entries (entry_no)
      )
    ''');

    await db.execute('CREATE TABLE suppliers (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, mobile TEXT, address TEXT, email TEXT, gst_in TEXT, dl_number TEXT, current_balance REAL DEFAULT 0.0, is_active INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE patients (id TEXT PRIMARY KEY, name TEXT NOT NULL, mobile TEXT, address TEXT, email TEXT, current_balance REAL DEFAULT 0.0, is_active INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE doctors (id TEXT PRIMARY KEY, name TEXT NOT NULL, mobile TEXT, specialization TEXT, reg_no TEXT, is_active INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE sales_return_invoices (entry_no TEXT PRIMARY KEY, date TEXT NOT NULL, customer_acc TEXT, patient TEXT, doctor TEXT, sub_total REAL DEFAULT 0.0, discount REAL DEFAULT 0.0, tax REAL DEFAULT 0.0, round_off REAL DEFAULT 0.0, grand_total REAL, narration TEXT, gst_mode INTEGER DEFAULT 1, original_invoice_no TEXT, is_deleted INTEGER DEFAULT 0, is_imported INTEGER DEFAULT 0, financial_year TEXT)');
    await db.execute('CREATE TABLE sales_return_items (id INTEGER PRIMARY KEY AUTOINCREMENT, return_no TEXT, product_id TEXT, product_name TEXT, batch_number TEXT, expiry_date TEXT, quantity INTEGER, mrp REAL, sale_rate REAL, disc_percent REAL DEFAULT 0.0, disc_amt REAL DEFAULT 0.0, hsn_code TEXT, total REAL, purchase_rate REAL DEFAULT 0.0, landing_cost REAL DEFAULT 0.0, supplier_name TEXT, packing INTEGER DEFAULT 1, gst_percent REAL DEFAULT 12.0, FOREIGN KEY (return_no) REFERENCES sales_return_invoices (entry_no))');
    await db.execute('CREATE TABLE purchase_return_entries (entry_no TEXT PRIMARY KEY, date TEXT NOT NULL, supplier_name TEXT, original_purchase_no TEXT, done_by TEXT, grand_total REAL, is_deleted INTEGER DEFAULT 0, is_imported INTEGER DEFAULT 0, financial_year TEXT)');
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

    // Performance Indexes
    await db.execute('CREATE INDEX idx_product_name ON product_master(name)');
    await db.execute('CREATE INDEX idx_product_generic ON product_master(generic_name)');
    await db.execute('CREATE INDEX idx_pm_name_nocase ON product_master(name COLLATE NOCASE)');
    await db.execute('CREATE INDEX idx_pm_generic_nocase ON product_master(generic_name COLLATE NOCASE)');
    await db.execute('CREATE INDEX idx_batch_expiry ON stock_batches(expiry_date)');
    await db.execute('CREATE INDEX idx_sales_items_invoice ON sales_items(invoice_no)');
    await db.execute('CREATE INDEX idx_purchase_items_entry ON purchase_items(entry_no)');
    await db.execute('CREATE INDEX idx_sales_patient ON sales_invoices(patient)');
    await db.execute('CREATE INDEX idx_purchase_supplier ON purchase_entries(supplier_name)');
    await db.execute('CREATE INDEX idx_sales_date_fy ON sales_invoices(date, financial_year, is_deleted)');
    await db.execute('CREATE INDEX idx_pur_date_fy ON purchase_entries(date, financial_year, is_deleted)');
    await db.execute('CREATE INDEX idx_monthly_close ON monthly_closing_balances(closing_month_year)');
  }

  Future<void> close() async {
    final db = await database;
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
      await sourceFile.copy(targetPath);
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

  Future<void> cleanupOldBackups({int keepDays = 30}) async {
    try {
      final dbPath = await getDatabasesPath();
      final backupDir = Directory(join(dbPath, 'backups'));
      if (await backupDir.exists()) {
        final cutoff = DateTime.now().subtract(Duration(days: keepDays));
        final List<FileSystemEntity> files = backupDir.listSync();

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
        final List<FileSystemEntity> files = backupDir.listSync();
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

  static final _txLock = _AsyncLock();

  Future<T> executeSerializedTransaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return await _txLock.synchronized(() async {
      return await db.transaction((txn) async {
        return await action(txn);
      });
    });
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
}

class _AsyncLock {
  Future<void>? _last;

  Future<T> synchronized<T>(Future<T> Function() action) async {
    final previous = _last;
    final completer = Completer<void>();
    _last = completer.future;

    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }

    try {
      return await action();
    } finally {
      completer.complete();
    }
  }
}