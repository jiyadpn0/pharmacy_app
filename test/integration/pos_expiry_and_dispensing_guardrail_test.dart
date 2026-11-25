import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/utils/app_validators.dart';
import 'package:pharmacy_app/models/erp_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DbHelper.instance.setMockDatabase(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT PRIMARY KEY,
        name TEXT,
        phone TEXT,
        address TEXT,
        gst_in TEXT,
        dl_number TEXT,
        current_balance REAL DEFAULT 0.0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS patients (
        id TEXT PRIMARY KEY,
        name TEXT,
        mobile TEXT,
        address TEXT,
        email TEXT,
        is_active INTEGER DEFAULT 1,
        current_balance REAL DEFAULT 0.0
      )
    ''');
  });

  tearDown(() async {
    DbHelper.instance.setMockDatabase(null);
    await db.close();
  });

  group('Pillar 9: Real-time POS Expiry Guardrail & Dispensing Interceptor Tests', () {
    test('POS Expiry Interceptor detects and blocks expired batches at point of sale', () {
      final billingDate = DateTime(2026, 3, 15);

      const validBatchExp = '05/27';
      const nearExpBatch = '04/26'; // ~45 days from March 15, 2026
      const expiredBatch = '01/24'; // Expired in Jan 2024
      const isoExpiredBatch = '2025-12-31';

      // 1. Expired batches must be detected as expired
      expect(AppValidators.isExpired(expiredBatch, asOf: billingDate), isTrue);
      expect(AppValidators.isExpired(isoExpiredBatch, asOf: billingDate), isTrue);

      // 2. Valid batch must NOT be expired
      expect(AppValidators.isExpired(validBatchExp, asOf: billingDate), isFalse);

      // 3. Near-expiry detection within 60 days
      expect(AppValidators.isNearExpiry(nearExpBatch, thresholdDays: 60, asOf: billingDate), isTrue);
      expect(AppValidators.isNearExpiry(validBatchExp, thresholdDays: 60, asOf: billingDate), isFalse);
    });

    test('Inward Purchase Expiry Guardrail prevents receiving expired stock from suppliers', () {
      final invoiceDate = DateTime(2026, 3, 10);

      // Distributor sends batch expiring 02/2026 (expired relative to March 2026)
      const supplierExpiredBatch = '02/26';
      expect(AppValidators.isExpired(supplierExpiredBatch, asOf: invoiceDate), isTrue);

      // Fresh stock expiring in 2028 is accepted
      const freshStockBatch = '10/28';
      expect(AppValidators.isExpired(freshStockBatch, asOf: invoiceDate), isFalse);
    });

    test('Master Ledger Registration validates Supplier GSTIN, Drug License and Phone', () async {
      // 1. Valid Supplier
      const validGstin = '32AAAAA0000A1Z5';
      const validDl = 'KL-TVM-12345';
      const validPhone = '9876543210';

      expect(AppValidators.isValidGstin(validGstin), isTrue);
      expect(AppValidators.isValidDrugLicense(validDl), isTrue);
      expect(AppValidators.isValidPhone(validPhone), isTrue);

      final supplier = Supplier(
        id: 'SUP_001',
        name: 'MEDICHEM DISTRIBUTORS',
        phone: AppValidators.sanitizePhone(validPhone),
        gstIn: validGstin,
        dlNumber: validDl,
      );

      await db.insert('suppliers', supplier.toMap());
      final saved = await db.query('suppliers', where: 'id = ?', whereArgs: ['SUP_001']);
      expect(saved.length, equals(1));
      expect(saved.first['gst_in'], equals(validGstin));
      expect(saved.first['dl_number'], equals(validDl));

      // 2. Invalid inputs are rejected
      expect(AppValidators.isValidGstin('INVALID_GSTIN'), isFalse);
      expect(AppValidators.isValidDrugLicense('ABC'), isFalse);
      expect(AppValidators.isValidPhone('12345'), isFalse);
    });

    test('Patient Registration enforces 10-digit Indian Mobile format', () async {
      expect(AppValidators.isValidPhone('9876543210'), isTrue);
      expect(AppValidators.isValidPhone('+919876543210'), isTrue);
      expect(AppValidators.isValidPhone('5876543210'), isFalse); // Non 6-9 leading digit

      final patient = Patient(
        id: 'PAT_001',
        name: 'RAHUL SHARMA',
        mobile: AppValidators.sanitizePhone('+91 98765-43210'),
      );

      await db.insert('patients', patient.toMap());
      final saved = await db.query('patients', where: 'id = ?', whereArgs: ['PAT_001']);
      expect(saved.length, equals(1));
      expect(saved.first['mobile'], equals('9876543210'));
    });
  });
}
