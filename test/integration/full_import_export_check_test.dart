// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pharmacy_app/services/excel_worker_service.dart';

void main() {
  const supabaseUrl = 'https://awnfbjvvvtdzcluekwjl.supabase.co';
  const apiKey = 'sb_publishable_VVg6DhhXbaRjytujA0dkEw_BBg7BYWS';

  final headers = {
    'apikey': apiKey,
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  group('Complete Import & Export Health Check', () {
    test('1. Local SQLite Health & Master Product / Rack Counts', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dbPath = await databaseFactory.getDatabasesPath();
      final fullPath = p.join(dbPath, 'pharmacy.db');

      final db = await databaseFactory.openDatabase(fullPath);

      final pmCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM product_master')) ?? 0;
      final racksCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM racks')) ?? 0;
      final nonNullRacks = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM product_master WHERE rack_id IS NOT NULL AND rack_id != ''")) ?? 0;

      final cilacar = await db.rawQuery("SELECT id, name, rack_id FROM product_master WHERE name LIKE '%CILACAR 10 TAB%'");

      print('--------------------------------------------------');
      print('📊 LOCAL SQLITE STATUS:');
      print('   • Total Products in Master: $pmCount');
      print('   • Total Registered Racks: $racksCount');
      print('   • Products with Assigned Racks: $nonNullRacks');
      print('   • CILACAR 10 TAB Sample: $cilacar');
      print('--------------------------------------------------');

      expect(pmCount, greaterThan(0));
      expect(racksCount, greaterThan(0));
      await db.close();
    });

    test('2. Excel / CSV Import Engine Verification', () async {
      const csvPath = r'J:\PHARMACY\pharmacy data\21092026\PRODUCTS_LISTS.csv';
      final file = File(csvPath);
      if (!file.existsSync()) {
        print('⚠️ CSV file not found at $csvPath. Skipping raw file parse test.');
        return;
      }

      final rawRows = await ExcelWorkerService.parseExcelRawRowsInBackground(csvPath);
      expect(rawRows, isNotEmpty);

      final header = rawRows.first.map((e) => e.toLowerCase().trim()).toList();
      final hasName = header.contains('name');
      final hasRack = header.contains('rack');

      print('--------------------------------------------------');
      print('📂 CSV IMPORT ENGINE STATUS:');
      print('   • Total Rows Parsed: ${rawRows.length}');
      print('   • Has Name Column: $hasName');
      print('   • Has Rack Column: $hasRack');
      print('--------------------------------------------------');

      expect(hasName, isTrue);
      expect(hasRack, isTrue);
    });

    test('3. Cloud REST Connection & Export/Import Verification', () async {
      // 1. Fetch Cloud Products (Export test)
      final getRes = await http.get(
        Uri.parse('$supabaseUrl/rest/v1/product_master?select=id,product_name,rack&limit=5'),
        headers: headers,
      );

      print('--------------------------------------------------');
      print('☁️ SUPABASE CLOUD STATUS:');
      print('   • Product Master Read Status: ${getRes.statusCode}');
      if (getRes.statusCode == 200) {
        final List list = jsonDecode(getRes.body);
        print('   • Sample Cloud Products Fetched: ${list.length}');
      }
      expect(getRes.statusCode, equals(200));

      // 2. Insert test product & verify rack round-trip (Import test)
      final testId = 'TEST_EXPORT_${DateTime.now().millisecondsSinceEpoch}';
      final postHeaders = Map<String, String>.from(headers)..['Prefer'] = 'return=representation';

      final postRes = await http.post(
        Uri.parse('$supabaseUrl/rest/v1/product_master'),
        headers: postHeaders,
        body: jsonEncode({
          'id': testId,
          'product_name': 'AUTO_TEST_PRODUCT',
          'rack': 'T99',
          'branch_id': 'MAIN_STORE',
        }),
      );

      print('   • Test Product Write Status: ${postRes.statusCode}');
      expect(postRes.statusCode, equals(201));

      // Verify rack stored properly in cloud
      final verifyRes = await http.get(
        Uri.parse('$supabaseUrl/rest/v1/product_master?id=eq.$testId&select=id,product_name,rack'),
        headers: headers,
      );
      final List verifyList = jsonDecode(verifyRes.body);
      expect(verifyList, isNotEmpty);
      expect(verifyList.first['rack'], equals('T99'));
      print('   • Rack T99 Verified on Cloud Successfully!');

      // Cleanup
      await http.delete(Uri.parse('$supabaseUrl/rest/v1/product_master?id=eq.$testId'), headers: headers);
      print('   • Test Product Cleaned Up.');
      print('--------------------------------------------------');
    });
  });
}
