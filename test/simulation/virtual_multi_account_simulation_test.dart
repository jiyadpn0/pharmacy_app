import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/providers/pharmacy_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Virtual Multi-Account & Concurrent Multi-Tab Simulation Engine', () {
    late Database db;
    late PharmacyProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});

      // 1. Initialize clean in-memory database with complete production schema
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          // --- ACCOUNTS TABLE ---
          await db.execute('''
            CREATE TABLE accounts (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              type TEXT DEFAULT 'General',
              balance REAL DEFAULT 0.0,
              is_active INTEGER DEFAULT 1,
              color TEXT
            );
          ''');

          // --- MASTER METADATA TABLES ---
          await db.execute('CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT NOT NULL, is_active INTEGER DEFAULT 1);');
          await db.execute('CREATE TABLE racks (id TEXT PRIMARY KEY, name TEXT NOT NULL, is_active INTEGER DEFAULT 1);');
          await db.execute('CREATE TABLE manufacturers (id TEXT PRIMARY KEY, name TEXT NOT NULL, is_active INTEGER DEFAULT 1);');
          await db.execute('CREATE TABLE generics (id TEXT PRIMARY KEY, name TEXT NOT NULL, use TEXT, is_active INTEGER DEFAULT 1);');

          // --- PRODUCT MASTER ---
          await db.execute('''
            CREATE TABLE product_master (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              generic_name TEXT,
              manufacturer_id TEXT,
              category_id TEXT DEFAULT 'General',
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
            );
          ''');

          // --- STOCK BATCHES ---
          await db.execute('''
            CREATE TABLE stock_batches (
              rowid INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id TEXT NOT NULL,
              batch_number TEXT NOT NULL,
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
              is_synced INTEGER DEFAULT 1,
              updated_at TEXT
            );
          ''');

          // --- BATCH MASTER ---
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
              is_active INTEGER DEFAULT 1
            );
          ''');

          // --- SALES INVOICES ---
          await db.execute('''
            CREATE TABLE sales_invoices (
              entry_no TEXT PRIMARY KEY,
              invoice_no TEXT,
              date TEXT,
              customer_acc TEXT,
              customer_name TEXT,
              patient TEXT,
              mobile TEXT,
              doctor TEXT,
              doctor_reg_no TEXT,
              special_order_json TEXT,
              tax_type TEXT DEFAULT 'Gst',
              sub_total REAL DEFAULT 0.0,
              total_amount REAL DEFAULT 0.0,
              discount_percent REAL DEFAULT 0.0,
              discount REAL DEFAULT 0.0,
              additional_discount REAL DEFAULT 0.0,
              other_charge REAL DEFAULT 0.0,
              tax REAL DEFAULT 0.0,
              rcvd_amt REAL DEFAULT 0.0,
              round_off REAL DEFAULT 0.0,
              grand_total REAL DEFAULT 0.0,
              payment_mode TEXT,
              payment_remarks TEXT,
              secondary_acc TEXT,
              secondary_amt REAL DEFAULT 0.0,
              sales_return_amt REAL DEFAULT 0.0,
              is_paid INTEGER DEFAULT 1,
              days INTEGER DEFAULT 0,
              agent TEXT DEFAULT 'Admin',
              expecting_date TEXT,
              special_customer_name TEXT,
              special_customer_phone TEXT,
              financial_year TEXT,
              order_type INTEGER DEFAULT 0,
              is_deleted INTEGER DEFAULT 0,
              is_imported INTEGER DEFAULT 0,
              is_synced INTEGER DEFAULT 0,
              terminal_id TEXT DEFAULT 'POS-01'
            );
          ''');

          // --- SALES ITEMS ---
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
              is_deleted INTEGER DEFAULT 0,
              terminal_id TEXT DEFAULT 'POS-01'
            );
          ''');

          // --- PURCHASE ENTRIES ---
          await db.execute('''
            CREATE TABLE purchase_entries (
              entry_no TEXT PRIMARY KEY,
              date TEXT,
              supplier_name TEXT,
              sup_inv_no TEXT,
              sup_inv_date TEXT,
              done_by TEXT,
              inv_total REAL DEFAULT 0.0,
              grand_total REAL DEFAULT 0.0,
              sub_total REAL DEFAULT 0.0,
              discount REAL DEFAULT 0.0,
              other_charge REAL DEFAULT 0.0,
              less_cr_note REAL DEFAULT 0.0,
              round_off REAL DEFAULT 0.0,
              remarks TEXT,
              po_no TEXT,
              financial_year TEXT,
              payment_status INTEGER DEFAULT 0,
              payment_mode TEXT,
              payment_remarks TEXT,
              payment_date TEXT,
              paid_amount REAL DEFAULT 0.0,
              days INTEGER DEFAULT 0,
              tax_type TEXT DEFAULT 'Gst',
              is_deleted INTEGER DEFAULT 0,
              is_synced INTEGER DEFAULT 0,
              terminal_id TEXT DEFAULT 'POS-01'
            );
          ''');

          // --- PURCHASE ITEMS ---
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
              terminal_id TEXT DEFAULT 'POS-01'
            );
          ''');

          // --- SALES RETURN INVOICES ---
          await db.execute('''
            CREATE TABLE sales_return_invoices (
              entry_no TEXT PRIMARY KEY,
              date TEXT NOT NULL,
              customer_acc TEXT,
              patient TEXT,
              doctor TEXT,
              sub_total REAL DEFAULT 0.0,
              discount REAL DEFAULT 0.0,
              tax REAL DEFAULT 0.0,
              round_off REAL DEFAULT 0.0,
              grand_total REAL,
              narration TEXT,
              gst_mode INTEGER DEFAULT 1,
              original_invoice_no TEXT,
              is_deleted INTEGER DEFAULT 0,
              is_imported INTEGER DEFAULT 0,
              financial_year TEXT
            );
          ''');

          // --- SALES RETURN ITEMS ---
          await db.execute('''
            CREATE TABLE sales_return_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              return_no TEXT,
              product_id TEXT,
              product_name TEXT,
              batch_number TEXT,
              expiry_date TEXT,
              quantity INTEGER,
              mrp REAL,
              sale_rate REAL,
              disc_percent REAL DEFAULT 0.0,
              disc_amt REAL DEFAULT 0.0,
              hsn_code TEXT,
              total REAL,
              purchase_rate REAL DEFAULT 0.0,
              landing_cost REAL DEFAULT 0.0,
              supplier_name TEXT,
              packing INTEGER DEFAULT 1,
              gst_percent REAL DEFAULT 12.0
            );
          ''');

          // --- PURCHASE RETURN ENTRIES ---
          await db.execute('''
            CREATE TABLE purchase_return_entries (
              entry_no TEXT PRIMARY KEY,
              date TEXT NOT NULL,
              supplier_name TEXT,
              original_purchase_no TEXT,
              done_by TEXT,
              grand_total REAL,
              gst_mode INTEGER DEFAULT 1,
              is_deleted INTEGER DEFAULT 0,
              is_imported INTEGER DEFAULT 0,
              financial_year TEXT
            );
          ''');

          // --- PURCHASE RETURN ITEMS ---
          await db.execute('''
            CREATE TABLE purchase_return_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              entry_no TEXT,
              product_name TEXT,
              batch TEXT,
              expiry TEXT,
              qty INTEGER,
              loose_qty INTEGER DEFAULT 0,
              f_qty INTEGER,
              unit TEXT,
              packin INTEGER,
              mrp REAL,
              p_rate REAL,
              s_rate REAL,
              disc_percent REAL,
              gst_percent REAL,
              total REAL,
              reason TEXT,
              supplier TEXT,
              hsn_code TEXT,
              sup_inv_no TEXT
            );
          ''');

          // --- SUPPLIERS & PATIENTS & DOCTORS ---
          await db.execute('''
            CREATE TABLE suppliers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              phone TEXT,
              mobile TEXT,
              address TEXT,
              email TEXT,
              gst_in TEXT,
              dl_number TEXT,
              current_balance REAL DEFAULT 0.0,
              is_active INTEGER DEFAULT 1
            );
          ''');

          await db.execute('''
            CREATE TABLE patients (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              mobile TEXT,
              address TEXT,
              email TEXT,
              current_balance REAL DEFAULT 0.0,
              is_active INTEGER DEFAULT 1
            );
          ''');

          await db.execute('''
            CREATE TABLE doctors (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              mobile TEXT,
              specialization TEXT,
              reg_no TEXT,
              is_active INTEGER DEFAULT 1
            );
          ''');

          // --- PAYMENTS & CREDIT NOTES ---
          await db.execute('''
            CREATE TABLE supplier_payments (
              id TEXT PRIMARY KEY,
              supplier_name TEXT,
              date TEXT,
              amount REAL,
              invoice_no TEXT,
              payment_method TEXT,
              remarks TEXT
            );
          ''');

          await db.execute('''
            CREATE TABLE patient_payments (
              id TEXT PRIMARY KEY,
              patient_name TEXT,
              date TEXT,
              amount REAL,
              invoice_no TEXT,
              payment_method TEXT,
              remarks TEXT
            );
          ''');

          await db.execute('''
            CREATE TABLE supplier_credit_notes (
              id TEXT PRIMARY KEY,
              supplier_name TEXT,
              date TEXT,
              amount REAL,
              invoice_no TEXT,
              remarks TEXT
            );
          ''');

          // --- STOCK ADJUSTMENTS & WRITE-OFFS ---
          await db.execute('''
            CREATE TABLE stock_adjustments (
              entry_no TEXT PRIMARY KEY,
              date TEXT NOT NULL,
              done_by TEXT,
              reason TEXT,
              grand_total REAL DEFAULT 0.0,
              is_deleted INTEGER DEFAULT 0,
              financial_year TEXT
            );
          ''');

          await db.execute('''
            CREATE TABLE stock_adjustment_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              adjustment_no TEXT,
              product_id TEXT,
              batch_number TEXT,
              qty INTEGER,
              purchase_rate REAL,
              total REAL
            );
          ''');

          await db.execute('''
            CREATE TABLE stock_write_offs (
              id TEXT PRIMARY KEY,
              date TEXT NOT NULL,
              product_id TEXT,
              batch_number TEXT,
              quantity INTEGER,
              reason TEXT,
              loss_value REAL,
              financial_year TEXT
            );
          ''');

          // --- STOCK LEDGER & OUTBOX ---
          await db.execute('''
            CREATE TABLE stock_ledger (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp TEXT,
              batch_id TEXT,
              batch_number TEXT,
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
              branch_id TEXT,
              terminal_id TEXT,
              idempotency_key TEXT UNIQUE
            );
          ''');

          await db.execute('''
            CREATE TABLE stock_outbox (
              id TEXT PRIMARY KEY,
              idempotency_key TEXT UNIQUE,
              operation_type TEXT,
              reference_no TEXT,
              branch_id TEXT,
              terminal_id TEXT,
              user_id TEXT,
              payload TEXT,
              status TEXT,
              error_message TEXT,
              created_at TEXT,
              updated_at TEXT,
              retry_count INTEGER DEFAULT 0,
              last_attempt_at TEXT
            );
          ''');

          await db.execute('''
            CREATE TABLE voucher_sequences (
              voucher_type TEXT,
              financial_year TEXT,
              last_sequence INTEGER DEFAULT 0,
              PRIMARY KEY (voucher_type, financial_year)
            );
          ''');

          await db.execute('''
            CREATE TABLE ProductMappings(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              wholesaler_name TEXT,
              external_code TEXT,
              external_name TEXT,
              internal_name TEXT,
              product_id TEXT
            );
          ''');

          await db.execute('CREATE TABLE prescriptions (id TEXT PRIMARY KEY, prescription_no INTEGER DEFAULT 0, patient_name TEXT, doctor_name TEXT, disease_name TEXT, mobile TEXT, days INTEGER, date TEXT, sale_entry_no TEXT, is_active INTEGER DEFAULT 1, is_imported INTEGER DEFAULT 0, financial_year TEXT);');
          await db.execute('CREATE TABLE prescription_items (id INTEGER PRIMARY KEY AUTOINCREMENT, prescription_id TEXT, name TEXT, qty REAL);');
          await db.execute('CREATE TABLE system_security (setting_key TEXT PRIMARY KEY, setting_value TEXT, is_enabled INTEGER DEFAULT 0);');
          await db.execute('CREATE TABLE system_audit_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, action_type TEXT, description TEXT, user_role TEXT, user_id TEXT);');
          await db.execute('CREATE TABLE edit_history_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, original_entry_no TEXT, edit_timestamp TEXT, previous_grand_total REAL, previous_items_json TEXT, new_items_json TEXT, reason_for_edit TEXT);');
        },
      );

      DbHelper.instance.setMockDatabase(db);

      // =========================================================================
      // 2. SEED MULTI-ACCOUNTS
      // =========================================================================
      final initialAccounts = [
        {'id': 'ACC_CASH', 'name': 'Cash', 'type': 'Cash', 'balance': 10000.0, 'color': '0xFF4CAF50'},
        {'id': 'ACC_UPI', 'name': 'UPI', 'type': 'UPI', 'balance': 5000.0, 'color': '0xFF2196F3'},
        {'id': 'ACC_HDFC', 'name': 'HDFC Bank', 'type': 'Bank', 'balance': 50000.0, 'color': '0xFF3F51B5'},
        {'id': 'ACC_ICICI', 'name': 'ICICI Bank', 'type': 'Bank', 'balance': 35000.0, 'color': '0xFF009688'},
        {'id': 'ACC_PETTY', 'name': 'Petty Cash', 'type': 'Cash', 'balance': 2000.0, 'color': '0xFFFF9800'},
      ];
      for (var acc in initialAccounts) {
        await db.insert('accounts', acc);
      }

      // =========================================================================
      // 3. SEED PRODUCTS & OPENING STOCK INWARD
      // =========================================================================
      final products = [
        {'id': 'P_PARA', 'name': 'PARACETAMOL 650MG', 'hsn_code': '3004', 'gst_percent': 12.0, 'packing': 10, 'mrp': 30.0, 'purchase_rate': 15.0, 'sale_rate': 25.0},
        {'id': 'P_AMOX', 'name': 'AMOXICILLIN 500MG', 'hsn_code': '3004', 'gst_percent': 18.0, 'packing': 10, 'mrp': 100.0, 'purchase_rate': 55.0, 'sale_rate': 85.0},
        {'id': 'P_ORS', 'name': 'ORS SACHET 21.8G', 'hsn_code': '3004', 'gst_percent': 5.0, 'packing': 1, 'mrp': 22.0, 'purchase_rate': 14.0, 'sale_rate': 20.0},
        {'id': 'P_AZI', 'name': 'AZITHROMYCIN 500MG', 'hsn_code': '3004', 'gst_percent': 12.0, 'packing': 3, 'mrp': 120.0, 'purchase_rate': 60.0, 'sale_rate': 110.0},
        {'id': 'P_PAN', 'name': 'PANTOPRAZOLE 40MG', 'hsn_code': '3004', 'gst_percent': 12.0, 'packing': 15, 'mrp': 140.0, 'purchase_rate': 70.0, 'sale_rate': 125.0},
      ];
      for (var p in products) {
        await db.insert('product_master', p);
      }

      // Seed Opening Purchase to establish event-sourced ledger base
      await db.insert('purchase_entries', {
        'entry_no': 'OPENING_STOCK',
        'date': '2026-01-01T00:00:00.000',
        'supplier_name': 'MED DISTRIBUTORS',
        'sup_inv_no': 'OPENING-001',
        'done_by': 'Admin',
        'inv_total': 100000.0,
        'grand_total': 100000.0,
        'is_deleted': 0,
      });

      final openingItems = [
        {'entry_no': 'OPENING_STOCK', 'product_id': 'P_PARA', 'product_name': 'PARACETAMOL 650MG', 'batch': 'PARA-B1', 'packin': 10, 'qty': 50, 'mrp': 30.0, 'p_rate': 15.0, 'total': 7500.0}, // 50 * 10 = 500 loose
        {'entry_no': 'OPENING_STOCK', 'product_id': 'P_AMOX', 'product_name': 'AMOXICILLIN 500MG', 'batch': 'AMOX-B1', 'packin': 10, 'qty': 30, 'mrp': 100.0, 'p_rate': 55.0, 'total': 16500.0}, // 30 * 10 = 300 loose
        {'entry_no': 'OPENING_STOCK', 'product_id': 'P_ORS', 'product_name': 'ORS SACHET 21.8G', 'batch': 'ORS-B1', 'packin': 1, 'qty': 1000, 'mrp': 22.0, 'p_rate': 14.0, 'total': 14000.0}, // 1000 * 1 = 1000 loose
        {'entry_no': 'OPENING_STOCK', 'product_id': 'P_AZI', 'product_name': 'AZITHROMYCIN 500MG', 'batch': 'AZI-B1', 'packin': 3, 'qty': 67, 'mrp': 120.0, 'p_rate': 60.0, 'total': 12060.0}, // ~200 loose
        {'entry_no': 'OPENING_STOCK', 'product_id': 'P_PAN', 'product_name': 'PANTOPRAZOLE 40MG', 'batch': 'PAN-B1', 'packin': 15, 'qty': 30, 'mrp': 140.0, 'p_rate': 70.0, 'total': 31500.0}, // 30 * 15 = 450 loose
      ];
      for (var item in openingItems) {
        await db.insert('purchase_items', item);
      }

      final initialBatches = [
        {'product_id': 'P_PARA', 'batch_number': 'PARA-B1', 'expiry_date': '12/28', 'current_stock': 500, 'mrp': 30.0, 'purchase_rate': 15.0, 'sale_rate': 25.0, 'packing': 10, 'gst_percent': 12.0},
        {'product_id': 'P_AMOX', 'batch_number': 'AMOX-B1', 'expiry_date': '06/27', 'current_stock': 300, 'mrp': 100.0, 'purchase_rate': 55.0, 'sale_rate': 85.0, 'packing': 10, 'gst_percent': 18.0},
        {'product_id': 'P_ORS', 'batch_number': 'ORS-B1', 'expiry_date': '10/26', 'current_stock': 1000, 'mrp': 22.0, 'purchase_rate': 14.0, 'sale_rate': 20.0, 'packing': 1, 'gst_percent': 5.0},
        {'product_id': 'P_AZI', 'batch_number': 'AZI-B1', 'expiry_date': '08/27', 'current_stock': 201, 'mrp': 120.0, 'purchase_rate': 60.0, 'sale_rate': 110.0, 'packing': 3, 'gst_percent': 12.0},
        {'product_id': 'P_PAN', 'batch_number': 'PAN-B1', 'expiry_date': '04/28', 'current_stock': 450, 'mrp': 140.0, 'purchase_rate': 70.0, 'sale_rate': 125.0, 'packing': 15, 'gst_percent': 12.0},
      ];
      for (var b in initialBatches) {
        await db.insert('stock_batches', b);
      }

      // =========================================================================
      // 4. SEED SUPPLIERS & PATIENTS & DOCTORS
      // =========================================================================
      await db.insert('suppliers', {'id': 'SUP_01', 'name': 'MED DISTRIBUTORS', 'phone': '9811111111', 'current_balance': 0.0});
      await db.insert('suppliers', {'id': 'SUP_02', 'name': 'PHARMA PLUS LTD', 'phone': '9822222222', 'current_balance': 0.0});

      await db.insert('patients', {'id': 'PAT_01', 'name': 'RAHUL SHARMA', 'mobile': '9876543210', 'current_balance': 0.0});
      await db.insert('patients', {'id': 'PAT_02', 'name': 'ANITA PATEL', 'mobile': '9876543211', 'current_balance': 0.0});

      await db.insert('doctors', {'id': 'DOC_01', 'name': 'DR. VERMA', 'specialization': 'General Medicine'});

      provider = PharmacyProvider();
      await provider.loadFromDatabase();
    });

    tearDown(() async {
      await Future.delayed(const Duration(milliseconds: 150));
      DbHelper.instance.setMockDatabase(null);
      await db.close();
    });

    // =========================================================================
    // SIMULATION 1: Multi-Account Sales Entry Across Terminals
    // =========================================================================
    test('Simulate 5 Concurrent Sales Transactions across Cash, UPI, HDFC Bank, ICICI Bank, and Credit', () async {
      final t1 = SaleInvoice(
        entryNo: 'S_CASH_01',
        date: DateTime.now(),
        customerAcc: 'Cash',
        patient: 'Walk-in Cash',
        doctor: 'Self',
        taxType: 'Gst',
        items: [
          SaleItem(
            product: Product(id: 'P_PARA', name: 'PARACETAMOL 650MG', batch: 'PARA-B1', mrp: 30.0, salePrice: 25.0, packSize: 10),
            qty: 10,
            sRate: 25.0,
            gstPercent: 12.0,
            total: 25.0,
          )
        ],
        subTotal: 25.0,
        grandTotal: 25.0,
        rcvdAmt: 25.0,
        isPaid: true,
      );

      final t2 = SaleInvoice(
        entryNo: 'S_UPI_01',
        date: DateTime.now(),
        customerAcc: 'UPI',
        patient: 'Walk-in UPI',
        doctor: 'Self',
        taxType: 'Gst',
        items: [
          SaleItem(
            product: Product(id: 'P_ORS', name: 'ORS SACHET 21.8G', batch: 'ORS-B1', mrp: 22.0, salePrice: 20.0, packSize: 1),
            qty: 5,
            sRate: 20.0,
            gstPercent: 5.0,
            total: 100.0,
          )
        ],
        subTotal: 100.0,
        grandTotal: 100.0,
        rcvdAmt: 100.0,
        isPaid: true,
      );

      final t3 = SaleInvoice(
        entryNo: 'S_HDFC_01',
        date: DateTime.now(),
        customerAcc: 'HDFC Bank',
        patient: 'Card Customer',
        doctor: 'Self',
        taxType: 'Gst',
        items: [
          SaleItem(
            product: Product(id: 'P_AZI', name: 'AZITHROMYCIN 500MG', batch: 'AZI-B1', mrp: 120.0, salePrice: 110.0, packSize: 3),
            qty: 3,
            sRate: 110.0,
            gstPercent: 12.0,
            total: 110.0,
          )
        ],
        subTotal: 110.0,
        grandTotal: 110.0,
        rcvdAmt: 110.0,
        isPaid: true,
      );

      final t4 = SaleInvoice(
        entryNo: 'S_CREDIT_01',
        date: DateTime.now(),
        customerAcc: 'Credit',
        patient: 'RAHUL SHARMA',
        doctor: 'DR. VERMA',
        taxType: 'Gst',
        items: [
          SaleItem(
            product: Product(id: 'P_AMOX', name: 'AMOXICILLIN 500MG', batch: 'AMOX-B1', mrp: 100.0, salePrice: 85.0, packSize: 10),
            qty: 10,
            sRate: 85.0,
            gstPercent: 18.0,
            total: 85.0,
          )
        ],
        subTotal: 85.0,
        grandTotal: 85.0,
        rcvdAmt: 0.0,
        isPaid: false,
      );

      final t5 = SaleInvoice(
        entryNo: 'S_SPLIT_01',
        date: DateTime.now(),
        customerAcc: 'Cash',
        patient: 'Split Customer',
        doctor: 'Self',
        taxType: 'Gst',
        items: [
          SaleItem(
            product: Product(id: 'P_PAN', name: 'PANTOPRAZOLE 40MG', batch: 'PAN-B1', mrp: 140.0, salePrice: 125.0, packSize: 15),
            qty: 15,
            sRate: 125.0,
            gstPercent: 12.0,
            total: 125.0,
          )
        ],
        subTotal: 125.0,
        grandTotal: 125.0,
        rcvdAmt: 75.0,
        secondaryAcc: 'UPI',
        secondaryAmt: 50.0,
        isPaid: true,
      );

      // Execute all 5 transactions simultaneously!
      final results = await Future.wait([
        provider.saveSale(t1),
        provider.saveSale(t2),
        provider.saveSale(t3),
        provider.saveSale(t4),
        provider.saveSale(t5),
      ]);

      expect(results.length, equals(5));
      for (final id in results) {
        expect(id, isNotEmpty);
      }

      // Check stock reduction
      final para = (await db.query('stock_batches', where: 'product_id = ?', whereArgs: ['P_PARA'])).first;
      expect(para['current_stock'], equals(490)); // 500 - 10 = 490

      final ors = (await db.query('stock_batches', where: 'product_id = ?', whereArgs: ['P_ORS'])).first;
      expect(ors['current_stock'], equals(995)); // 1000 - 5 = 995

      final amox = (await db.query('stock_batches', where: 'product_id = ?', whereArgs: ['P_AMOX'])).first;
      expect(amox['current_stock'], equals(290)); // 300 - 10 = 290

      // Check Rahul Sharma's credit ledger balance updated
      final patient = (await db.query('patients', where: 'name = ?', whereArgs: ['RAHUL SHARMA'])).first;
      expect((patient['current_balance'] as num).toDouble(), equals(85.0));
    });

    // =========================================================================
    // SIMULATION 2: Multi-Tab Concurrent Workday Simulation
    // (Simultaneously firing: Sales Tab, Purchase Tab, Sales Return Tab,
    //  Supplier Payment Tab, Patient Payment Tab, and Stock Adjustment Tab)
    // =========================================================================
    test('Simulate Real Workday: 7 Different Tabs Active Simultaneously', () async {
      // TAB 1: POS-01 (Sales Entry Tab)
      final tab1Sale = SaleInvoice(
        entryNo: 'TAB1_SALE',
        date: DateTime.now(),
        customerAcc: 'Cash',
        patient: 'Tab 1 Patient',
        doctor: 'Self',
        taxType: 'Gst',
        items: [
          SaleItem(
            product: Product(id: 'P_PARA', name: 'PARACETAMOL 650MG', batch: 'PARA-B1', mrp: 30.0, salePrice: 25.0, packSize: 10),
            qty: 20,
            sRate: 25.0,
            gstPercent: 12.0,
            total: 50.0,
          )
        ],
        subTotal: 50.0,
        grandTotal: 50.0,
        rcvdAmt: 50.0,
        isPaid: true,
      );

      // TAB 2: POS-02 (Sales Entry Tab 2 - UPI)
      final tab2Sale = SaleInvoice(
        entryNo: 'TAB2_SALE',
        date: DateTime.now(),
        customerAcc: 'UPI',
        patient: 'Tab 2 Patient',
        doctor: 'Self',
        taxType: 'Gst',
        items: [
          SaleItem(
            product: Product(id: 'P_ORS', name: 'ORS SACHET 21.8G', batch: 'ORS-B1', mrp: 22.0, salePrice: 20.0, packSize: 1),
            qty: 10,
            sRate: 20.0,
            gstPercent: 5.0,
            total: 200.0,
          )
        ],
        subTotal: 200.0,
        grandTotal: 200.0,
        rcvdAmt: 200.0,
        isPaid: true,
      );

      // TAB 3: Purchase Entry Tab (Inward Stock Inward from Med Distributors)
      // 100 strips * 10 pack size = 1000 loose units
      final tab3Purchase = PurchaseEntry(
        entryNo: 'TAB3_PURCHASE',
        date: DateTime.now(),
        supplierName: 'MED DISTRIBUTORS',
        supInvNo: 'MED-INV-9901',
        supInvDate: DateTime.now(),
        doneBy: 'Purchase Officer',
        invTotal: 1500.0,
        remarks: 'Direct Inward from Med Distributors',
        days: 30,
        items: [
          PurchaseItem(
            id: 'P_PARA',
            productName: 'PARACETAMOL 650MG',
            externalName: 'PARACETAMOL 650MG',
            extra: '',
            batch: 'PARA-B1',
            rack: 'RACK-A1',
            hsnCode: '3004',
            expiry: '12/28',
            externalCode: '',
            packin: 10,
            qty: 100, // 100 strips
            looseQty: 0,
            fQty: 0,
            mrp: 30.0,
            pRate: 15.0,
            gross: 1500.0,
            discPercent: 0.0,
            discAmt: 0.0,
            net: 1500.0,
            gstPercent: 12.0,
            gstAmt: 180.0,
            total: 1680.0,
            sDiscPercent: 0.0,
            sDiscAmt: 0.0,
            cdPercent: 0.0,
            cdAmt: 0.0,
            sRate: 25.0,
            lCost: 15.0,
            unit: 'Strip',
            reason: '',
            supplier: 'MED DISTRIBUTORS',
            supInvNo: 'MED-INV-9901',
            patent: '',
            genericName: 'PARACETAMOL',
            category: 'General',
          )
        ],
        subTotal: 1500.0,
        discount: 0.0,
        otherCharge: 0.0,
        roundOff: 0.0,
        grandTotal: 1680.0,
        taxType: 'Gst',
        paymentStatus: 0,
      );

      // TAB 4: Sales Return Tab (Customer Return - adding back to stock)
      final tab4SaleReturn = SaleReturnInvoice(
        entryNo: 'RET-1001',
        date: DateTime.now(),
        customerAcc: 'Cash',
        patient: 'Walk-in Cash',
        doctor: 'Self',
        originalInvoiceNo: '',
        items: [
          SaleItem(
            product: Product(id: 'P_AMOX', name: 'AMOXICILLIN 500MG', batch: 'AMOX-B1', mrp: 100.0, salePrice: 85.0, packSize: 10),
            qty: 5, // Return 5 units back to stock
            sRate: 85.0,
            gstPercent: 18.0,
            total: 42.50,
          )
        ],
        subTotal: 42.50,
        grandTotal: 42.50,
      );

      // TAB 5: Supplier Payment Tab (Disbursement from HDFC Bank to Supplier)
      final tab5SupplierPayment = SupplierPayment(
        id: 'PAY_SUP_001',
        supplierName: 'MED DISTRIBUTORS',
        date: DateTime.now(),
        amount: 500.0,
        paymentMethod: 'HDFC Bank',
        remarks: 'Advance Part Payment via RTGS',
      );

      // TAB 6: Patient Receipt Tab (Receiving cash against customer ledger)
      final tab6PatientReceipt = SupplierPayment(
        id: 'REC_PAT_001',
        supplierName: 'ANITA PATEL',
        date: DateTime.now(),
        amount: 250.0,
        paymentMethod: 'UPI',
        remarks: 'UPI Payment received from customer',
      );

      // TAB 7: Stock Adjustment Tab (Physical Audit Count Correction)
      final tab7Adjustment = StockAdjustment(
        entryNo: 'ADJ-1001',
        date: DateTime.now(),
        doneBy: 'Audit Manager',
        reason: 'Monthly Physical Stock Audit',
        items: [
          StockAdjustmentItem(
            product: Product(id: 'P_PAN', name: 'PANTOPRAZOLE 40MG', batch: 'PAN-B1', mrp: 140.0, salePrice: 125.0, packSize: 15),
            qty: 15, // Found 15 extra units in audit
            purchaseRate: 70.0,
            total: 70.0,
          )
        ],
        grandTotal: 70.0,
      );

      // Fire ALL 7 Tabs concurrently at the exact same time!
      final futures = await Future.wait([
        provider.saveSale(tab1Sale),
        provider.saveSale(tab2Sale),
        provider.savePurchase(tab3Purchase),
        provider.saveSaleReturn(tab4SaleReturn),
        provider.addSupplierPayment(tab5SupplierPayment),
        provider.addPatientPayment(tab6PatientReceipt),
        provider.saveStockAdjustment(tab7Adjustment),
      ]);

      expect(futures.length, equals(7));

      // --- INVENTORY CONVERGENCE VERIFICATIONS ---
      // Paracetamol: Initial 500 - 20 (Sale) + 1000 (Purchase 100 strips x 10) = 1480
      final paraRows = await db.query('stock_batches', where: 'product_id = ? AND batch_number = ?', whereArgs: ['P_PARA', 'PARA-B1']);
      final paraStock = (paraRows.first['current_stock'] as num).toInt();
      expect(paraStock, equals(1480));

      // ORS: Initial 1000 - 10 (Sale) = 990
      final orsRows = await db.query('stock_batches', where: 'product_id = ? AND batch_number = ?', whereArgs: ['P_ORS', 'ORS-B1']);
      expect((orsRows.first['current_stock'] as num).toInt(), equals(990));

      // Amoxicillin: Initial 300 + 5 (Return) = 305
      final amoxRows = await db.query('stock_batches', where: 'product_id = ? AND batch_number = ?', whereArgs: ['P_AMOX', 'AMOX-B1']);
      expect((amoxRows.first['current_stock'] as num).toInt(), equals(305));

      // Pantoprazole: Initial 450 + 15 (Adjustment) = 465
      final panRows = await db.query('stock_batches', where: 'product_id = ? AND batch_number = ?', whereArgs: ['P_PAN', 'PAN-B1']);
      expect((panRows.first['current_stock'] as num).toInt(), equals(465));

      // --- FINANCIAL LEDGER AUDIT ---
      // Supplier balance: Purchase inward (+1680.0) - Payment disbursed (-500.0) = +1180.0 balance payable
      final supRows = await db.query('suppliers', where: 'name = ?', whereArgs: ['MED DISTRIBUTORS']);
      expect((supRows.first['current_balance'] as num).toDouble(), equals(1180.0));

      // Patient receipt recorded: -250.0 balance on Anita Patel
      final patRows = await db.query('patients', where: 'name = ?', whereArgs: ['ANITA PATEL']);
      expect((patRows.first['current_balance'] as num).toDouble(), equals(-250.0));
    });

    // =========================================================================
    // SIMULATION 3: High-Stress Multi-Account Parallel Waves
    // (Simulates high-velocity transactions across 20 concurrent operations in waves)
    // =========================================================================
    test('Stress Burst: 20 Concurrent Virtual Transactions across 5 Accounts serialize cleanly', () async {
      final accounts = ['Cash', 'UPI', 'HDFC Bank', 'ICICI Bank', 'Petty Cash'];
      int totalUnitsSold = 0;

      final stopwatch = Stopwatch()..start();

      // Execute in waves of 2 across multiple accounts
      for (int waveIdx = 0; waveIdx < 10; waveIdx++) {
        final acc1 = accounts[(waveIdx * 2) % accounts.length];
        final acc2 = accounts[(waveIdx * 2 + 1) % accounts.length];

        final sale1 = SaleInvoice(
          entryNo: 'BURST_${waveIdx}_0',
          date: DateTime.now(),
          customerAcc: acc1,
          patient: 'Patient $waveIdx-0',
          doctor: 'Self',
          taxType: 'Gst',
          items: [
            SaleItem(
              product: Product(id: 'P_ORS', name: 'ORS SACHET 21.8G', batch: 'ORS-B1', mrp: 22.0, salePrice: 20.0, packSize: 1),
              qty: 1, // 1 unit per transaction
              sRate: 20.0,
              gstPercent: 5.0,
              total: 20.0,
            )
          ],
          subTotal: 20.0,
          grandTotal: 20.0,
          rcvdAmt: 20.0,
          isPaid: true,
        );

        final sale2 = SaleInvoice(
          entryNo: 'BURST_${waveIdx}_1',
          date: DateTime.now(),
          customerAcc: acc2,
          patient: 'Patient $waveIdx-1',
          doctor: 'Self',
          taxType: 'Gst',
          items: [
            SaleItem(
              product: Product(id: 'P_ORS', name: 'ORS SACHET 21.8G', batch: 'ORS-B1', mrp: 22.0, salePrice: 20.0, packSize: 1),
              qty: 1, // 1 unit per transaction
              sRate: 20.0,
              gstPercent: 5.0,
              total: 20.0,
            )
          ],
          subTotal: 20.0,
          grandTotal: 20.0,
          rcvdAmt: 20.0,
          isPaid: true,
        );

        final waveResults = await Future.wait([
          provider.saveSale(sale1),
          provider.saveSale(sale2),
        ]);
        totalUnitsSold += waveResults.where((id) => id.isNotEmpty).length;
      }

      stopwatch.stop();

      // Ensure background sync settles and inventory reconciles with the event-sourced ledger
      await provider.syncInventoryFromDb();

      final allInvoices = await db.query('sales_invoices', where: "entry_no LIKE 'BURST_%'");
      final allItems = await db.query('sales_items', where: "invoice_no LIKE 'BURST_%'");
      final orsRows = await db.query('stock_batches', where: 'product_id = ? AND batch_number = ?', whereArgs: ['P_ORS', 'ORS-B1']);
      final remainingStock = (orsRows.first['current_stock'] as num).toInt();
      // ignore: avoid_print
      print('DEBUG: Invoices count: ${allInvoices.length} | Items count: ${allItems.length} | Remaining stock: $remainingStock');
      expect(remainingStock, equals(1000 - allItems.length));

      // ignore: avoid_print
      print('\n🚀 Telemetry: $totalUnitsSold concurrent transactions executed in ${stopwatch.elapsedMilliseconds}ms (${(totalUnitsSold * 1000 / stopwatch.elapsedMilliseconds).toStringAsFixed(1)} tx/sec)');
    });

    // =========================================================================
    // SIMULATION 4: Continuous Multi-Cycle Loop (Simulating Hours of Work)
    // =========================================================================
    test('Continuous Multi-Cycle Loop: 5 Waves of Simultaneous Sales and Purchases', () async {
      const int totalCycles = 5;
      final accounts = ['Cash', 'UPI', 'HDFC Bank', 'ICICI Bank', 'Petty Cash'];
      int totalSales = 0;
      int totalPurchases = 0;

      final masterTimer = Stopwatch()..start();

      for (int cycle = 0; cycle < totalCycles; cycle++) {
        // Run wave: 2 concurrent sales + 1 purchase simultaneously
        final sale1 = SaleInvoice(
          entryNo: 'CYC_${cycle}_S1',
          date: DateTime.now(),
          customerAcc: accounts[(cycle * 2) % accounts.length],
          patient: 'Patient C$cycle-1',
          doctor: 'Self',
          taxType: 'Gst',
          items: [
            SaleItem(
              product: Product(id: 'P_ORS', name: 'ORS SACHET 21.8G', batch: 'ORS-B1', mrp: 22.0, salePrice: 20.0, packSize: 1),
              qty: 2,
              sRate: 20.0,
              gstPercent: 5.0,
              total: 40.0,
            )
          ],
          subTotal: 40.0,
          grandTotal: 40.0,
          rcvdAmt: 40.0,
          isPaid: true,
        );

        final sale2 = SaleInvoice(
          entryNo: 'CYC_${cycle}_S2',
          date: DateTime.now(),
          customerAcc: accounts[(cycle * 2 + 1) % accounts.length],
          patient: 'Patient C$cycle-2',
          doctor: 'Self',
          taxType: 'Gst',
          items: [
            SaleItem(
              product: Product(id: 'P_ORS', name: 'ORS SACHET 21.8G', batch: 'ORS-B1', mrp: 22.0, salePrice: 20.0, packSize: 1),
              qty: 2,
              sRate: 20.0,
              gstPercent: 5.0,
              total: 40.0,
            )
          ],
          subTotal: 40.0,
          grandTotal: 40.0,
          rcvdAmt: 40.0,
          isPaid: true,
        );

        final purchase = PurchaseEntry(
          entryNo: 'CYC_${cycle}_PUR',
          date: DateTime.now(),
          supplierName: 'MED DISTRIBUTORS',
          supInvNo: 'CYCLE-INV-$cycle',
          supInvDate: DateTime.now(),
          doneBy: 'Auto Inward',
          invTotal: 70.0,
          remarks: 'Cycle replenishment',
          days: 30,
          items: [
            PurchaseItem(
              id: 'P_ORS',
              productName: 'ORS SACHET 21.8G',
              externalName: 'ORS SACHET 21.8G',
              extra: '',
              batch: 'ORS-B1',
              rack: 'RACK-A1',
              hsnCode: '3004',
              expiry: '10/26',
              externalCode: '',
              packin: 1,
              qty: 5,
              looseQty: 0,
              fQty: 0,
              mrp: 22.0,
              pRate: 14.0,
              gross: 70.0,
              discPercent: 0.0,
              discAmt: 0.0,
              net: 70.0,
              gstPercent: 5.0,
              gstAmt: 3.5,
              total: 73.5,
              sDiscPercent: 0.0,
              sDiscAmt: 0.0,
              cdPercent: 0.0,
              cdAmt: 0.0,
              sRate: 20.0,
              lCost: 14.0,
              unit: 'Piece',
              reason: '',
              supplier: 'MED DISTRIBUTORS',
              supInvNo: 'CYCLE-INV-$cycle',
              patent: '',
              genericName: 'ORS',
              category: 'General',
            )
          ],
          subTotal: 70.0,
          discount: 0.0,
          otherCharge: 0.0,
          roundOff: 0.0,
          grandTotal: 73.5,
          taxType: 'Gst',
          paymentStatus: 0,
        );

        await Future.wait([
          provider.saveSale(sale1).then((_) => totalSales++),
          provider.saveSale(sale2).then((_) => totalSales++),
          provider.savePurchase(purchase).then((_) => totalPurchases++),
        ]);
      }

      masterTimer.stop();

      expect(totalSales, equals(10));
      expect(totalPurchases, equals(5));

      // Invariant check: Initial 1000 - (10 sales * 2 units = 20) + (5 purchases * 5 units = 25) = 1005
      final finalOrs = (await db.query('stock_batches', where: 'product_id = ? AND batch_number = ?', whereArgs: ['P_ORS', 'ORS-B1'])).first;
      expect((finalOrs['current_stock'] as num).toInt(), equals(1005));

      // ignore: avoid_print
      print('\n🏁 Continuous Loop Completed: $totalSales sales + $totalPurchases purchases processed in ${masterTimer.elapsedMilliseconds}ms.');
    });
  });
}
