import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const supabaseUrl = 'https://awnfbjvvvtdzcluekwjl.supabase.co';
  const apiKey = 'sb_publishable_VVg6DhhXbaRjytujA0dkEw_BBg7BYWS';

  final headers = {
    'apikey': apiKey,
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  group('Server-Based Importing & Cloud Catalog Verification', () {
    test('Verify Master Catalog Download REST Endpoint Pagination', () async {
      final uri = Uri.parse('$supabaseUrl/rest/v1/product_master?select=id,name,purchase_rate,mrp&limit=10');
      final res = await http.get(uri, headers: headers);

      expect(res.statusCode, equals(200));
      final List<dynamic> list = jsonDecode(res.body);
      // ignore: avoid_print
      print('Product Master Sample Download: ${list.length} records fetched successfully.');
    });

    test('Verify Stock Batches Cloud Import & Foreign Key Constraints', () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testProdId = 'PROD_TEST_$timestamp';
      final testBatchId = 'BATCH_TEST_$timestamp';

      final postHeaders = Map<String, String>.from(headers)..['Prefer'] = 'return=representation';

      // 1. Insert parent product_master record first
      final pmRes = await http.post(
        Uri.parse('$supabaseUrl/rest/v1/product_master'),
        headers: postHeaders,
        body: jsonEncode({
          'id': testProdId,
          'product_name': 'TEST_PRODUCT_INTEGRATION',
          'name': 'TEST_PRODUCT_INTEGRATION',
          'packing': 1,
          'is_active': 1,
          'branch_id': 'MAIN_STORE',
        }),
      );

      // ignore: avoid_print
      print('Parent Product Master Status: ${pmRes.statusCode}');
      expect(pmRes.statusCode, equals(201));

      // 2. Insert stock_batches record
      final postRes = await http.post(
        Uri.parse('$supabaseUrl/rest/v1/stock_batches'),
        headers: postHeaders,
        body: jsonEncode({
          'id': testBatchId,
          'product_id': testProdId,
          'batch_number': 'B123',
          'expiry_date': '01/29',
          'current_stock': 100,
          'purchase_rate': 10.0,
          'mrp': 15.0,
          'sale_rate': 14.0,
          'branch_id': 'MAIN_STORE',
        }),
      );

      // ignore: avoid_print
      print('Batch Insert Status: ${postRes.statusCode}');
      expect(postRes.statusCode, equals(201));

      // 3. Cleanup test records
      await http.delete(Uri.parse('$supabaseUrl/rest/v1/stock_batches?id=eq.$testBatchId'), headers: headers);
      await http.delete(Uri.parse('$supabaseUrl/rest/v1/product_master?id=eq.$testProdId'), headers: headers);
    });
  });
}
