import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';

class ScheduleH1Record {
  final int? id;
  final String date;
  final String invoiceNo;
  final String productName;
  final String batchNumber;
  final double qty;
  final String patientName;
  final String patientContact;
  final String doctorName;
  final String doctorRegNo;

  ScheduleH1Record({
    this.id,
    required this.date,
    required this.invoiceNo,
    required this.productName,
    required this.batchNumber,
    required this.qty,
    required this.patientName,
    required this.patientContact,
    required this.doctorName,
    required this.doctorRegNo,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'invoice_no': invoiceNo,
        'product_name': productName,
        'batch_number': batchNumber,
        'qty': qty,
        'patient_name': patientName,
        'patient_contact': patientContact,
        'doctor_name': doctorName,
        'doctor_reg_no': doctorRegNo,
      };

  factory ScheduleH1Record.fromMap(Map<String, dynamic> map) => ScheduleH1Record(
        id: (map['id'] as num?)?.toInt(),
        date: map['date']?.toString() ?? '',
        invoiceNo: map['invoice_no']?.toString() ?? '',
        productName: map['product_name']?.toString() ?? '',
        batchNumber: map['batch_number']?.toString() ?? '',
        qty: (map['qty'] as num?)?.toDouble() ?? 0.0,
        patientName: map['patient_name']?.toString() ?? '',
        patientContact: map['patient_contact']?.toString() ?? '',
        doctorName: map['doctor_name']?.toString() ?? '',
        doctorRegNo: map['doctor_reg_no']?.toString() ?? '',
      );
}

class ScheduleH1RegisterService {
  static final ScheduleH1RegisterService instance = ScheduleH1RegisterService._internal();
  ScheduleH1RegisterService._internal();

  Future<Database> get _db async => await DbHelper.instance.database;

  /// Ensures schedule_h1_logs table exists
  Future<void> _ensureTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS schedule_h1_logs (
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
  }

  /// Logs a Schedule H1 restricted drug transaction
  Future<int> logTransaction(ScheduleH1Record record) async {
    final db = await _db;
    await _ensureTable(db);
    return await db.insert('schedule_h1_logs', record.toMap());
  }

  /// Fetches Schedule H1 transactions for Drug Inspector audit
  Future<List<ScheduleH1Record>> getRecords({String? fromDate, String? toDate}) async {
    final db = await _db;
    await _ensureTable(db);

    List<Map<String, dynamic>> rows;
    if (fromDate != null && toDate != null) {
      rows = await db.query(
        'schedule_h1_logs',
        where: 'date >= ? AND date <= ?',
        whereArgs: [fromDate, toDate],
        orderBy: 'date DESC, id DESC',
      );
    } else {
      rows = await db.query('schedule_h1_logs', orderBy: 'date DESC, id DESC');
    }

    return rows.map((r) => ScheduleH1Record.fromMap(r)).toList();
  }

  /// Generates statutory CSV string format for Drug Inspector compliance submission
  String exportToCsv(List<ScheduleH1Record> records) {
    final StringBuffer sb = StringBuffer();
    sb.writeln("SL,DATE,INVOICE NO,DRUG NAME,BATCH NO,QTY,PATIENT NAME,PATIENT CONTACT,DOCTOR NAME,DOCTOR REG NO");
    int sl = 1;
    for (var r in records) {
      sb.writeln('${sl++},"${r.date}","${r.invoiceNo}","${r.productName}","${r.batchNumber}",${r.qty},"${r.patientName}","${r.patientContact}","${r.doctorName}","${r.doctorRegNo}"');
    }
    return sb.toString();
  }
}
