import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const supabaseUrl = 'https://awnfbjvvvtdzcluekwjl.supabase.co';
  const apiKey = 'sb_publishable_VVg6DhhXbaRjytujA0dkEw_BBg7BYWS';

  test('Simulate 2 PCs saving Purchase Entry simultaneously against Supabase REST', () async {
    final headers = {
      'apikey': apiKey,
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final testEntry1 = 'TEST_CONCURRENT_$timestamp';

    // PC 1 Payload (POS-01)
    final pc1Payload = jsonEncode({
      'entry_no': testEntry1,
      'date': DateTime.now().toIso8601String(),
      'supplier_name': 'TEST_SUPP_PC1',
      'branch_id': 'MAIN_STORE',
      'terminal_id': 'POS-01',
      'grand_total': 100.0,
      'sub_total': 100.0,
    });

    // PC 2 Payload (POS-02) - Simultaneous save with SAME entry_no
    final pc2Payload = jsonEncode({
      'entry_no': testEntry1,
      'date': DateTime.now().toIso8601String(),
      'supplier_name': 'TEST_SUPP_PC2',
      'branch_id': 'MAIN_STORE',
      'terminal_id': 'POS-02',
      'grand_total': 200.0,
      'sub_total': 200.0,
    });

    // Fire simultaneous HTTP POSTs from 2 separate client threads at the exact same millisecond
    final results = await Future.wait([
      http.post(Uri.parse('$supabaseUrl/rest/v1/purchase_entries'), headers: headers, body: pc1Payload),
      http.post(Uri.parse('$supabaseUrl/rest/v1/purchase_entries'), headers: headers, body: pc2Payload),
    ]);

    final pc1Res = results[0];
    final pc2Res = results[1];

    // ignore: avoid_print
    print('PC 1 Status: ${pc1Res.statusCode} | Body: ${pc1Res.body}');
    // ignore: avoid_print
    print('PC 2 Status: ${pc2Res.statusCode} | Body: ${pc2Res.body}');

    // Verify at least one POST succeeded (HTTP 201 Created)
    final hasSuccess = pc1Res.statusCode == 201 || pc2Res.statusCode == 201;
    expect(hasSuccess, isTrue, reason: 'At least one PC must successfully save its entry.');

    // Cleanup test entry from Supabase Cloud
    await http.delete(
      Uri.parse('$supabaseUrl/rest/v1/purchase_entries?entry_no=eq.$testEntry1'),
      headers: headers,
    );
  });
}
