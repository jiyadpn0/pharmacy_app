import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/repositories/stock_repository.dart';
import 'package:pharmacy_app/utils/app_validators.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Pillar 8: Centralized AppValidators Unit Tests', () {
    test('isValidGstin strictly validates Indian GSTIN format and state codes', () {
      // Valid GSTINs with state codes 32 (Kerala), 29 (Karnataka), 07 (Delhi)
      expect(AppValidators.isValidGstin('32AAAAA0000A1Z5'), isTrue);
      expect(AppValidators.isValidGstin('29ABCDE1234F2Z5'), isTrue);
      expect(AppValidators.isValidGstin('07AAAAA0000A1Z5'), isTrue);
      expect(AppValidators.isValidGstin('97AAAAA0000A1Z5'), isTrue); // Other territory

      // Invalid GSTINs
      expect(AppValidators.isValidGstin(null), isFalse);
      expect(AppValidators.isValidGstin(''), isFalse);
      expect(AppValidators.isValidGstin('00AAAAA0000A1Z5'), isFalse); // Invalid state code 00
      expect(AppValidators.isValidGstin('50AAAAA0000A1Z5'), isFalse); // Invalid state code 50
      expect(AppValidators.isValidGstin('32AAAAA0000A1Z'), isFalse); // 14 chars
      expect(AppValidators.isValidGstin('32AAAAA0000A1Z55'), isFalse); // 16 chars
      expect(AppValidators.isValidGstin('32AAAAA0000A1!5'), isFalse); // Special character
      expect(AppValidators.isValidGstin('URD'), isFalse);
      expect(AppValidators.isValidGstin('9876543210'), isFalse);
    });

    test('isValidPan validates 10-character Indian PAN format', () {
      expect(AppValidators.isValidPan('ABCDE1234F'), isTrue);
      expect(AppValidators.isValidPan('BLZPK9876Q'), isTrue);

      expect(AppValidators.isValidPan(null), isFalse);
      expect(AppValidators.isValidPan(''), isFalse);
      expect(AppValidators.isValidPan('ABCDE12345'), isFalse); // Last char must be letter
      expect(AppValidators.isValidPan('12345ABCDE'), isFalse);
      expect(AppValidators.isValidPan('ABCD12345F'), isFalse); // Only 4 letters in prefix
      expect(AppValidators.isValidPan('ABCDE1234FG'), isFalse); // 11 chars
    });

    test('isValidPhone and sanitizePhone validate Indian mobile numbers', () {
      expect(AppValidators.isValidPhone('9876543210'), isTrue);
      expect(AppValidators.isValidPhone('+919876543210'), isTrue);
      expect(AppValidators.isValidPhone('+91 98765 43210'), isTrue);
      expect(AppValidators.isValidPhone('09876543210'), isTrue);
      expect(AppValidators.isValidPhone('6123456789'), isTrue);
      expect(AppValidators.isValidPhone('7123456789'), isTrue);
      expect(AppValidators.isValidPhone('8123456789'), isTrue);

      // Invalid phones
      expect(AppValidators.isValidPhone(null), isFalse);
      expect(AppValidators.isValidPhone(''), isFalse);
      expect(AppValidators.isValidPhone('5123456789'), isFalse); // Doesn't start with 6-9
      expect(AppValidators.isValidPhone('987654321'), isFalse); // 9 digits
      expect(AppValidators.isValidPhone('98765432100'), isFalse); // 11 digits

      // sanitizePhone
      expect(AppValidators.sanitizePhone('+91 98765-43210'), equals('9876543210'));
      expect(AppValidators.sanitizePhone('09876543210'), equals('9876543210'));
      expect(AppValidators.sanitizePhone('invalid'), equals(''));
    });

    test('isValidDrugLicense validates state Form 20/21 licenses', () {
      expect(AppValidators.isValidDrugLicense('KL-TVM-12345'), isTrue);
      expect(AppValidators.isValidDrugLicense('DL-20B-98765'), isTrue);
      expect(AppValidators.isValidDrugLicense('MH-NZ-1234/20'), isTrue);

      expect(AppValidators.isValidDrugLicense(null), isFalse);
      expect(AppValidators.isValidDrugLicense(''), isFalse);
      expect(AppValidators.isValidDrugLicense('ABC'), isFalse); // Too short
      expect(AppValidators.isValidDrugLicense('ABCDE'), isFalse); // No numeric component
    });

    test('isValidDoctorRegNo and isValidBatchNumber validate medical inputs', () {
      expect(AppValidators.isValidDoctorRegNo('KMC-12345'), isTrue);
      expect(AppValidators.isValidDoctorRegNo('MCI/54321'), isTrue);
      expect(AppValidators.isValidDoctorRegNo(''), isFalse);

      expect(AppValidators.isValidBatchNumber('PARA-B1'), isTrue);
      expect(AppValidators.isValidBatchNumber('24L098'), isTrue);
      expect(AppValidators.isValidBatchNumber(''), isFalse);
      expect(AppValidators.isValidBatchNumber(null), isFalse);
    });

    test('isValidHsn validates 4, 6, 8 digit HSN/SAC codes', () {
      expect(AppValidators.isValidHsn('3004'), isTrue);
      expect(AppValidators.isValidHsn('300490'), isTrue);
      expect(AppValidators.isValidHsn('30049099'), isTrue);

      expect(AppValidators.isValidHsn('300'), isFalse); // 3 digits
      expect(AppValidators.isValidHsn('30049'), isFalse); // 5 digits
      expect(AppValidators.isValidHsn('3004909'), isFalse); // 7 digits
      expect(AppValidators.isValidHsn('3004A'), isFalse); // Letter
    });

    test('parseExpiryToDate, isExpired, and isNearExpiry accurately process diverse formats', () {
      final refDate = DateTime(2026, 3, 1);

      // 1. MM/YY format: 05/26 -> end of May 2026
      final d1 = AppValidators.parseExpiryToDate('05/26');
      expect(d1, isNotNull);
      expect(d1!.year, equals(2026));
      expect(d1.month, equals(5));
      expect(d1.day, equals(31));

      // 2. MM/YYYY format: 12/2026 -> end of Dec 2026
      final d2 = AppValidators.parseExpiryToDate('12/2026');
      expect(d2, isNotNull);
      expect(d2!.year, equals(2026));
      expect(d2.month, equals(12));
      expect(d2.day, equals(31));

      // 3. ISO format: 2026-04-15
      final d3 = AppValidators.parseExpiryToDate('2026-04-15');
      expect(d3, isNotNull);
      expect(d3!.year, equals(2026));
      expect(d3.month, equals(4));
      expect(d3.day, equals(15));

      // 4. ISO month format: 2026-06 -> end of June 2026
      final d4 = AppValidators.parseExpiryToDate('2026-06');
      expect(d4, isNotNull);
      expect(d4!.year, equals(2026));
      expect(d4.month, equals(6));
      expect(d4.day, equals(30));

      // Expiry checks relative to refDate (2026-03-01)
      expect(AppValidators.isExpired('12/25', asOf: refDate), isTrue); // Expired Dec 2025
      expect(AppValidators.isExpired('05/26', asOf: refDate), isFalse); // Expires May 2026

      // Near expiry within 90 days from 2026-03-01 (March to May 30 is ~90 days)
      expect(AppValidators.isNearExpiry('04/26', asOf: refDate, thresholdDays: 90), isTrue); // April 2026 is ~60 days away
      expect(AppValidators.isNearExpiry('12/26', asOf: refDate, thresholdDays: 90), isFalse); // Dec 2026 is ~300 days away
    });
  });

  group('Pillar 8: StockRepository FEFO & Lot Isolation Tests', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      DbHelper.instance.setMockDatabase(db);

      await db.execute('''
        CREATE TABLE IF NOT EXISTS batch_master (
          batch_id TEXT PRIMARY KEY,
          product_id TEXT,
          batch_number TEXT,
          expiry_date TEXT,
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
          is_active INTEGER DEFAULT 1,
          created_at TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_ledger (
          ledger_id INTEGER PRIMARY KEY AUTOINCREMENT,
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
          idempotency_key TEXT
        )
      ''');
    });

    tearDown(() async {
      DbHelper.instance.setMockDatabase(null);
      await db.close();
    });

    test('getAvailableBatchesForProduct guarantees deterministic FEFO ordering across slash and ISO formats', () async {
      const prodId = 'PROD_PARACETAMOL';

      // Insert batches with mixed date formats:
      // Batch 1: 12/26 (Dec 2026)
      // Batch 2: 2026-04-15 (April 2026 - earliest)
      // Batch 3: 06/26 (June 2026)
      // Batch 4: 2026-08 (August 2026)
      // Batch 5: 01/24 (Expired Jan 2024)

      final batchesData = [
        {'id': 'B1', 'num': 'BATCH-DEC', 'exp': '12/26', 'stock': 10},
        {'id': 'B2', 'num': 'BATCH-APRIL', 'exp': '2026-04-15', 'stock': 15},
        {'id': 'B3', 'num': 'BATCH-JUNE', 'exp': '06/26', 'stock': 20},
        {'id': 'B4', 'num': 'BATCH-AUG', 'exp': '2026-08', 'stock': 25},
        {'id': 'B5', 'num': 'BATCH-EXP', 'exp': '01/24', 'stock': 30},
      ];

      for (var b in batchesData) {
        await db.insert('batch_master', {
          'batch_id': b['id'],
          'product_id': prodId,
          'batch_number': b['num'],
          'expiry_date': b['exp'],
          'is_active': 1,
          'mrp': 100.0,
        });

        await db.insert('stock_ledger', {
          'batch_id': b['id'],
          'product_id': prodId,
          'qty_in': b['stock'],
          'qty_out': 0,
        });
      }

      // Query without excludeExpired: all 5 batches returned, ordered by FEFO
      final allBatches = await StockRepository.instance.getAvailableBatchesForProduct(prodId);
      expect(allBatches.length, equals(5));

      // Correct chronological order:
      // 1. 01/24 (Jan 2024)
      // 2. 2026-04-15 (Apr 2026)
      // 3. 06/26 (Jun 2026)
      // 4. 2026-08 (Aug 2026)
      // 5. 12/26 (Dec 2026)
      expect(allBatches[0].batchNumber, equals('BATCH-EXP'));
      expect(allBatches[1].batchNumber, equals('BATCH-APRIL'));
      expect(allBatches[2].batchNumber, equals('BATCH-JUNE'));
      expect(allBatches[3].batchNumber, equals('BATCH-AUG'));
      expect(allBatches[4].batchNumber, equals('BATCH-DEC'));

      // Query with excludeExpired: true as of March 2026 -> only expired batch '01/24' excluded!
      final activeBatches = await StockRepository.instance.getAvailableBatchesForProduct(
        prodId,
        excludeExpired: true,
        asOf: DateTime(2026, 3, 1),
      );
      expect(activeBatches.length, equals(4));
      expect(activeBatches.any((b) => b.batchNumber == 'BATCH-EXP'), isFalse);
      expect(activeBatches.first.batchNumber, equals('BATCH-APRIL'));
    });

    test('findOrCreateBatch prevents lot merging when batch number matches but expiry or MRP differ', () async {
      const prodId = 'PROD_AMOXICILLIN';

      // First batch: BATCH-100 with expiry 05/26 and MRP 120.0
      final b1 = await StockRepository.instance.findOrCreateBatch(
        productId: prodId,
        batchNumber: 'BATCH-100',
        expiryDate: '05/26',
        purchaseRate: 80.0,
        mrp: 120.0,
      );

      // Caller adds stock to b1
      await db.insert('stock_ledger', {
        'batch_id': b1.batchId,
        'product_id': prodId,
        'qty_in': 50,
        'qty_out': 0,
      });

      // Scenario A: Same product, same batch number, matching expiry & MRP -> Reuses b1!
      final b2 = await StockRepository.instance.findOrCreateBatch(
        productId: prodId,
        batchNumber: 'BATCH-100',
        expiryDate: '05/26',
        purchaseRate: 80.0,
        mrp: 120.0,
      );
      expect(b2.batchId, equals(b1.batchId));

      // Scenario B: Same product, same batch number, but DIFFERENT EXPIRY (e.g. 11/27) -> Must create separate batch!
      final b3 = await StockRepository.instance.findOrCreateBatch(
        productId: prodId,
        batchNumber: 'BATCH-100',
        expiryDate: '11/27',
        purchaseRate: 85.0,
        mrp: 120.0,
      );
      expect(b3.batchId, isNot(equals(b1.batchId)));

      // Scenario C: Same product, same batch number, but DIFFERENT MRP (e.g. 150.0 vs 120.0) -> Must create separate batch!
      final b4 = await StockRepository.instance.findOrCreateBatch(
        productId: prodId,
        batchNumber: 'BATCH-100',
        expiryDate: '05/26',
        purchaseRate: 90.0,
        mrp: 150.0,
      );
      expect(b4.batchId, isNot(equals(b1.batchId)));
    });
  });
}
