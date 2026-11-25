import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/models/erp_models.dart';
import 'package:pharmacy_app/services/schedule_h1_register_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DbHelper.instance.setMockDatabase(db);

    await db.execute('''
      CREATE TABLE schedule_h1_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT,
        invoice_no TEXT,
        product_name TEXT,
        batch_number TEXT,
        qty REAL,
        patient_name TEXT,
        patient_contact TEXT,
        doctor_name TEXT,
        doctor_reg_no TEXT
      )
    ''');
  });

  tearDown(() async {
    DbHelper.instance.setMockDatabase(null);
    await db.close();
  });

  test('ScheduleH1RegisterService logs and queries regulated items from sale invoice', () async {
    final sale = SaleInvoice(
      entryNo: 'INV-2026-001',
      date: DateTime.parse('2026-03-30'),
      customerAcc: 'Cash',
      patient: 'Rahul Sharma',
      mobile: '9876543210',
      doctor: 'Dr. S. Mehta',
      doctorRegNo: 'MCI-998822',
      items: [
        SaleItem(
          product: Product(
            id: 'PROD_1',
            name: 'Alprazolam 0.5mg Tab',
            batch: 'ALP-901',
            schedule: 'H1',
            mrp: 50.0,
            salePrice: 45.0,
            packSize: 10,
          ),
          qty: 2,
          fQty: 0,
          packin: 10,
          sRate: 45.0,
          mrp: 50.0,
          discPercent: 0.0,
          gstPercent: 12.0,
        ),
        SaleItem(
          product: Product(
            id: 'PROD_2',
            name: 'Paracetamol 650mg',
            batch: 'PCM-112',
            schedule: '',
            mrp: 30.0,
            salePrice: 25.0,
            packSize: 10,
          ),
          qty: 1,
          fQty: 0,
          packin: 10,
          sRate: 25.0,
          mrp: 30.0,
          discPercent: 0.0,
          gstPercent: 12.0,
        ),
      ],
      grandTotal: 115.0,
    );

    // Act
    await ScheduleH1RegisterService.instance.logSaleTransaction(sale);

    // Verify
    final records = await ScheduleH1RegisterService.instance.getRecords(
      fromDate: '2026-03-01',
      toDate: '2026-03-31',
    );

    expect(records.length, 1);
    final r = records.first;
    expect(r.productName, 'Alprazolam 0.5mg Tab');
    expect(r.batchNumber, 'ALP-901');
    expect(r.qty, 20.0); // 2 packs * packin 10
    expect(r.patientName, 'Rahul Sharma');
    expect(r.patientContact, '9876543210');
    expect(r.doctorName, 'Dr. S. Mehta');
    expect(r.doctorRegNo, 'MCI-998822');

    // Test CSV Export
    final csv = ScheduleH1RegisterService.instance.exportToCsv(records);
    expect(csv.contains('SL,DATE,INVOICE NO,DRUG NAME'), isTrue);
    expect(csv.contains('Alprazolam 0.5mg Tab'), isTrue);
    expect(csv.contains('MCI-998822'), isTrue);
  });
}
