import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/erp_models.dart';
import '../services/supabase_sync_service.dart';

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
    final List<Map<String, dynamic>> maps = await db.query(
      'suppliers',
      where: 'is_deleted = 0 OR is_deleted IS NULL',
      orderBy: 'name ASC',
    );
    return maps.map((m) => Supplier.fromMap(m)).toList();
  }

  Future<void> insertSupplier(Supplier supplier) async {
    final db = await _db;
    final map = supplier.toMap();
    map['is_synced'] = 0;
    map['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await db.insert('suppliers', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSupplier(Supplier supplier) async {
    await _dbHelper.markDirtyAndUpdate(
      'suppliers',
      supplier.toMap(),
      'id = ?',
      [supplier.id],
    );
  }

  Future<void> deleteSupplier(String id) async {
    await _dbHelper.markDirtyAndUpdate('suppliers', {'is_deleted': 1}, 'id = ?', [id]);
    await _dbHelper.queueDeletion('suppliers', id);
  }

  // =========================================================
  // PATIENTS
  // =========================================================

  Future<List<Patient>> fetchPatients() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'patients',
      where: 'is_deleted = 0 OR is_deleted IS NULL',
      orderBy: 'name ASC',
    );
    return maps.map((m) => Patient.fromMap(m)).toList();
  }

  Future<void> insertPatient(Patient patient) async {
    final db = await _db;
    final map = patient.toMap();
    map['is_synced'] = 0;
    map['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await db.insert('patients', map, conflictAlgorithm: ConflictAlgorithm.replace);
    try {
      SupabaseSyncService.instance.pushCustomer(map);
    } catch (_) {}
  }

  Future<void> updatePatient(Patient patient) async {
    await _dbHelper.markDirtyAndUpdate(
      'patients',
      patient.toMap(),
      'id = ?',
      [patient.id],
    );
    try {
      SupabaseSyncService.instance.pushCustomer(patient.toMap());
    } catch (_) {}
  }

  Future<void> deletePatient(String id) async {
    await _dbHelper.markDirtyAndUpdate('patients', {'is_deleted': 1}, 'id = ?', [id]);
    await _dbHelper.queueDeletion('patients', id);
  }

  // =========================================================
  // DOCTORS
  // =========================================================

  Future<List<Doctor>> fetchDoctors() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'doctors',
      where: 'is_deleted = 0 OR is_deleted IS NULL',
      orderBy: 'name ASC',
    );
    return maps.map((m) => Doctor.fromMap(m)).toList();
  }

  Future<void> insertDoctor(Doctor doctor) async {
    final db = await _db;
    final map = doctor.toMap();
    map['is_synced'] = 0;
    map['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await db.insert('doctors', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateDoctor(Doctor doctor) async {
    await _dbHelper.markDirtyAndUpdate(
      'doctors',
      doctor.toMap(),
      'id = ?',
      [doctor.id],
    );
  }

  Future<void> deleteDoctor(String id) async {
    await _dbHelper.markDirtyAndUpdate('doctors', {'is_deleted': 1}, 'id = ?', [id]);
    await _dbHelper.queueDeletion('doctors', id);
  }

  // =========================================================
  // STAFF
  // =========================================================

  Future<List<Staff>> fetchStaff() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'staff',
      where: 'is_deleted = 0 OR is_deleted IS NULL',
      orderBy: 'name ASC',
    );
    return maps.map((m) => Staff.fromMap(m)).toList();
  }

  Future<void> insertStaff(Staff staff) async {
    final db = await _db;
    final map = staff.toMap();
    map['is_synced'] = 0;
    map['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await db.insert('staff', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateStaff(Staff staff) async {
    await _dbHelper.markDirtyAndUpdate(
      'staff',
      staff.toMap(),
      'id = ?',
      [staff.id],
    );
  }

  Future<void> deleteStaff(String id) async {
    await _dbHelper.markDirtyAndUpdate('staff', {'is_deleted': 1}, 'id = ?', [id]);
    await _dbHelper.queueDeletion('staff', id);
  }

  // =========================================================
  // ACCOUNTS / LEDGERS
  // =========================================================

  Future<List<Map<String, dynamic>>> fetchAccounts() async {
    final db = await _db;
    try {
      return await db.query(
        'accounts',
        where: 'is_deleted = 0 OR is_deleted IS NULL',
        orderBy: 'name ASC',
      );
    } catch (_) {
      return await db.query(
        'account_master',
        where: 'is_deleted = 0 OR is_deleted IS NULL',
        orderBy: 'name ASC',
      );
    }
  }

  Future<void> insertAccount(Map<String, dynamic> accountData) async {
    final db = await _db;
    final map = Map<String, dynamic>.from(accountData);
    map['is_synced'] = 0;
    map['updated_at'] = DateTime.now().toUtc().toIso8601String();
    try {
      await db.insert('accounts', map, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      await db.insert('account_master', map, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> updateAccount(String id, Map<String, dynamic> accountData) async {
    try {
      await _dbHelper.markDirtyAndUpdate('accounts', accountData, 'id = ?', [id]);
    } catch (_) {
      await _dbHelper.markDirtyAndUpdate('account_master', accountData, 'id = ?', [id]);
    }
  }

  Future<void> deleteAccount(String id) async {
    try {
      await _dbHelper.markDirtyAndUpdate('accounts', {'is_deleted': 1}, 'id = ?', [id]);
      await _dbHelper.queueDeletion('accounts', id);
    } catch (_) {
      await _dbHelper.markDirtyAndUpdate('account_master', {'is_deleted': 1}, 'id = ?', [id]);
      await _dbHelper.queueDeletion('account_master', id);
    }
  }

  // =========================================================
  // RACKS
  // =========================================================

  Future<List<Map<String, dynamic>>> fetchRacks() async {
    final db = await _db;
    return await db.query(
      'racks',
      where: 'is_deleted = 0 OR is_deleted IS NULL',
      orderBy: 'name ASC',
    );
  }

  Future<void> insertRack(String name, {bool isActive = true}) async {
    final db = await _db;
    await db.insert(
      'racks',
      {
        'id': name,
        'name': name,
        'is_active': isActive ? 1 : 0,
        'is_synced': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> deleteRack(String name) async {
    await _dbHelper.markDirtyAndUpdate(
      'racks',
      {'is_deleted': 1},
      'name = ? OR id = ?',
      [name, name],
    );
    await _dbHelper.queueDeletion('racks', name);
  }

  // =========================================================
  // GENERICS
  // =========================================================

  Future<List<Map<String, dynamic>>> fetchGenerics() async {
    final db = await _db;
    return await db.query(
      'generics',
      where: 'is_deleted = 0 OR is_deleted IS NULL',
      orderBy: 'name ASC',
    );
  }

  Future<void> insertGeneric(String name, {String use = '', bool isActive = true}) async {
    final db = await _db;
    await db.insert(
      'generics',
      {
        'id': name,
        'name': name,
        'use': use,
        'is_active': isActive ? 1 : 0,
        'is_synced': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteGeneric(String name) async {
    await _dbHelper.markDirtyAndUpdate(
      'generics',
      {'is_deleted': 1},
      'name = ? OR id = ?',
      [name, name],
    );
    await _dbHelper.queueDeletion('generics', name);
  }

  // =========================================================
  // CATEGORIES & MANUFACTURERS
  // =========================================================

  Future<List<Map<String, dynamic>>> fetchCategories() async {
    final db = await _db;
    return await db.query(
      'categories',
      where: 'is_deleted = 0 OR is_deleted IS NULL',
      orderBy: 'name ASC',
    );
  }

  Future<void> insertCategory(String name) async {
    final db = await _db;
    await db.insert(
      'categories',
      {
        'id': name,
        'name': name,
        'is_synced': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> fetchManufacturers() async {
    final db = await _db;
    return await db.query(
      'manufacturers',
      where: 'is_deleted = 0 OR is_deleted IS NULL',
      orderBy: 'name ASC',
    );
  }

  Future<void> insertManufacturer(String name) async {
    final db = await _db;
    await db.insert(
      'manufacturers',
      {
        'id': name,
        'name': name,
        'is_synced': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> deleteManufacturer(String name) async {
    await _dbHelper.markDirtyAndUpdate(
      'manufacturers',
      {'is_deleted': 1},
      'name = ? OR id = ?',
      [name, name],
    );
    await _dbHelper.queueDeletion('manufacturers', name);
  }
}
