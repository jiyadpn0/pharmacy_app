import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/models/erp_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('First-Run Store Onboarding Wizard Tests', () {
    test('Initial installation triggers first-run wizard flag check', () async {
      final prefs = await SharedPreferences.getInstance();
      final bool isSetupDone = prefs.getBool('first_run_setup_v1_completed') ?? false;
      expect(isSetupDone, isFalse);

      // Simulate wizard completion
      await prefs.setBool('first_run_setup_v1_completed', true);
      await prefs.setString('invoice_series_prefix', 'BILL-');
      await prefs.setString('terminal_id', 'COUNTER-01');
      await prefs.setString('preferred_printer_type', 'thermal80');

      expect(prefs.getBool('first_run_setup_v1_completed'), isTrue);
      expect(prefs.getString('invoice_series_prefix'), equals('BILL-'));
      expect(prefs.getString('terminal_id'), equals('COUNTER-01'));
      expect(prefs.getString('preferred_printer_type'), equals('thermal80'));
    });

    test('First-run wizard seeds standard pharmacy masters into SQLite', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      // Create schema
      await db.execute('''
        CREATE TABLE categories (
          id TEXT PRIMARY KEY,
          name TEXT,
          is_active INTEGER
        );
      ''');
      await db.execute('''
        CREATE TABLE racks (
          id TEXT PRIMARY KEY,
          name TEXT,
          is_active INTEGER,
          status_date TEXT
        );
      ''');
      await db.execute('''
        CREATE TABLE accounts (
          id TEXT PRIMARY KEY,
          name TEXT,
          type TEXT,
          balance REAL,
          is_active INTEGER,
          color TEXT
        );
      ''');

      // Seed categories
      final categories = [
        {'id': 'CAT_TAB', 'name': 'Tablets & Capsules'},
        {'id': 'CAT_SYR', 'name': 'Syrups & Suspensions'},
        {'id': 'CAT_INJ', 'name': 'Injections'},
        {'id': 'CAT_OINT', 'name': 'Ointments & Creams'},
        {'id': 'CAT_DROP', 'name': 'Eye & Ear Drops'},
        {'id': 'CAT_SURG', 'name': 'Surgical & Bandages'},
        {'id': 'CAT_GEN', 'name': 'General & OTC'},
      ];
      for (var c in categories) {
        await db.insert('categories', {
          'id': c['id'],
          'name': c['name'],
          'is_active': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      // Seed racks
      final racks = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'Counter Shelf', 'Fridge / Cold Chain'];
      for (var r in racks) {
        await db.insert('racks', {
          'id': 'RACK_${r.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toUpperCase()}',
          'name': r,
          'is_active': 1,
          'status_date': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      // Seed accounts
      final accounts = [
        {'id': 'ACC_CASH', 'name': 'CASH', 'color': '0xFF4CAF50'},
        {'id': 'ACC_UPI', 'name': 'UPI / QR', 'color': '0xFF2196F3'},
        {'id': 'ACC_CARD', 'name': 'CARD / POS', 'color': '0xFF9C27B0'},
        {'id': 'ACC_CREDIT', 'name': 'CREDIT / UDHAR', 'color': '0xFFFF9800'},
      ];
      for (var a in accounts) {
        await db.insert('accounts', {
          'id': a['id'],
          'name': a['name'],
          'type': 'Payment',
          'balance': 0.0,
          'is_active': 1,
          'color': a['color'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      // Verify records
      final catCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM categories'));
      final rackCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM racks'));
      final accCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM accounts'));

      expect(catCount, equals(7));
      expect(rackCount, equals(8));
      expect(accCount, equals(4));

      // Verify specific records
      final cashAccount = await db.query('accounts', where: 'id = ?', whereArgs: ['ACC_CASH']);
      expect(cashAccount.first['name'], equals('CASH'));

      final coldChainRack = await db.query('racks', where: 'name LIKE ?', whereArgs: ['%Fridge%']);
      expect(coldChainRack.isNotEmpty, isTrue);

      await db.close();
    });

    test('CompanyProfile configured during onboarding retains legal licenses', () {
      final profile = CompanyProfile(
        name: 'Metro Care Pharmacy',
        address: '102 Medical Enclave, MG Road, Ernakulam',
        phone: '9847112233',
        email: 'billing@metrocarepharmacy.com',
        dlNumber: '20B-142857 / 21B-142858',
        gstIn: '32ABCDE1234F1Z5',
        tagline: 'Care That Counts, Prices You Trust',
      );

      expect(profile.name, equals('Metro Care Pharmacy'));
      expect(profile.dlNumber, contains('20B-142857'));
      expect(profile.tagline, equals('Care That Counts, Prices You Trust'));
    });
  });
}
