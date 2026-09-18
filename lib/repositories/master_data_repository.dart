import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/erp_models.dart';

/// Repository handling database operations for Master Data entities:
/// Suppliers, Patients, Doctors, Staff, Accounts, Racks, Generics, Categories, Manufacturers.
class MasterDataRepository {
  final DbHelper _dbHelper;

  MasterDataRepository({DbHelper? dbHelper})
      : _dbHelper = dbHelper ?? DbHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  // =========================================================
  // SUPPLIERS
  // =========================================================

  Future<List<Supplier>> fetchSuppliers() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps =
        await db.query('suppliers', orderBy: 'name ASC');
    return maps.map((m) => Supplier.fromMap(m)).toList();
  }

  Future<void> insertSupplier(Supplier supplier) async {
    final db = await _db;
    await db.insert('suppliers', supplier.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSupplier(Supplier supplier) async {
    final db = await _db;
    await db.update('suppliers', supplier.toMap(),
        where: 'id = ?', whereArgs: [supplier.id]);
  }

  Future<void> deleteSupplier(String id) async {
    final db = await _db;
    await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }

  // =========================================================
  // PATIENTS
  // =========================================================

  Future<List<Patient>> fetchPatients() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps =
        await db.query('patients', orderBy: 'name ASC');
    return maps.map((m) => Patient.fromMap(m)).toList();
  }

  Future<void> insertPatient(Patient patient) async {
    final db = await _db;
    await db.insert('patients', patient.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePatient(Patient patient) async {
    final db = await _db;
    await db.update('patients', patient.toMap(),
        where: 'id = ?', whereArgs: [patient.id]);
  }

  Future<void> deletePatient(String id) async {
    final db = await _db;
    await db.delete('patients', where: 'id = ?', whereArgs: [id]);
  }

  // =========================================================
  // DOCTORS
  // =========================================================

  Future<List<Doctor>> fetchDoctors() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps =
        await db.query('doctors', orderBy: 'name ASC');
    return maps.map((m) => Doctor.fromMap(m)).toList();
  }

  Future<void> insertDoctor(Doctor doctor) async {
    final db = await _db;
    await db.insert('doctors', doctor.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateDoctor(Doctor doctor) async {
    final db = await _db;
    await db.update('doctors', doctor.toMap(),
        where: 'id = ?', whereArgs: [doctor.id]);
  }

  Future<void> deleteDoctor(String id) async {
    final db = await _db;
    await db.delete('doctors', where: 'id = ?', whereArgs: [id]);
  }

  // =========================================================
  // STAFF
  // =========================================================

  Future<List<Staff>> fetchStaff() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps =
        await db.query('staff', orderBy: 'name ASC');
    return maps.map((m) => Staff.fromMap(m)).toList();
  }

  Future<void> insertStaff(Staff staff) async {
    final db = await _db;
    await db.insert('staff', staff.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateStaff(Staff staff) async {
    final db = await _db;
    await db.update('staff', staff.toMap(),
        where: 'id = ?', whereArgs: [staff.id]);
  }

  Future<void> deleteStaff(String id) async {
    final db = await _db;
    await db.delete('staff', where: 'id = ?', whereArgs: [id]);
  }

  // =========================================================
  // ACCOUNTS / LEDGERS
  // =========================================================

  Future<List<Map<String, dynamic>>> fetchAccounts() async {
    final db = await _db;
    return await db.query('account_master', orderBy: 'name ASC');
  }

  Future<void> insertAccount(Map<String, dynamic> accountData) async {
    final db = await _db;
    await db.insert('account_master', accountData,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateAccount(String id, Map<String, dynamic> accountData) async {
    final db = await _db;
    await db.update('account_master', accountData,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAccount(String id) async {
    final db = await _db;
    await db.delete('account_master', where: 'id = ?', whereArgs: [id]);
  }

  // =========================================================
  // RACKS
  // =========================================================

  Future<List<Map<String, dynamic>>> fetchRacks() async {
    final db = await _db;
    return await db.query('racks', orderBy: 'name ASC');
  }

  Future<void> insertRack(String name, {bool isActive = true}) async {
    final db = await _db;
    await db.insert(
      'racks',
      {'name': name, 'is_active': isActive ? 1 : 0},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> deleteRack(String name) async {
    final db = await _db;
    await db.delete('racks', where: 'name = ?', whereArgs: [name]);
  }

  // =========================================================
  // GENERICS
  // =========================================================

  Future<List<Map<String, dynamic>>> fetchGenerics() async {
    final db = await _db;
    return await db.query('generics', orderBy: 'name ASC');
  }

  Future<void> insertGeneric(String name, {String use = '', bool isActive = true}) async {
    final db = await _db;
    await db.insert(
      'generics',
      {'name': name, 'use': use, 'is_active': isActive ? 1 : 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteGeneric(String name) async {
    final db = await _db;
    await db.delete('generics', where: 'name = ?', whereArgs: [name]);
  }

  // =========================================================
  // CATEGORIES & MANUFACTURERS
  // =========================================================

  Future<List<Map<String, dynamic>>> fetchCategories() async {
    final db = await _db;
    return await db.query('categories', orderBy: 'name ASC');
  }

  Future<void> insertCategory(String name) async {
    final db = await _db;
    await db.insert(
      'categories',
      {'name': name},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> fetchManufacturers() async {
    final db = await _db;
    return await db.query('manufacturers', orderBy: 'name ASC');
  }

  Future<void> insertManufacturer(String name) async {
    final db = await _db;
    await db.insert(
      'manufacturers',
      {'name': name},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> deleteManufacturer(String name) async {
    final db = await _db;
    await db.delete('manufacturers', where: 'name = ?', whereArgs: [name]);
  }
}
