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
    'Prefer': 'return=representation',
  };

  group('Server-Based Saving & Outbox Export Verification', () {
    test('Simultaneous Sales Invoice Save from 2 Counters', () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testInvNo = 'TEST_SALE_$timestamp';

      final pos1Payload = jsonEncode({
        'invoice_no': testInvNo,
        'entry_no': testInvNo,
        'financial_year': '2026-27',
        'date': DateTime.now().toIso8601String(),
        'customer_name': 'Patient POS-01',
        'branch_id': 'MAIN_STORE',
        'terminal_id': 'POS-01',
        'grand_total': 150.0,
        'sub_total': 150.0,
        'payment_mode': 'CASH',
        'is_deleted': 0,
      });

      final pos2Payload = jsonEncode({
        'invoice_no': testInvNo,
        'entry_no': testInvNo,
        'financial_year': '2026-27',
        'date': DateTime.now().toIso8601String(),
        'customer_name': 'Patient POS-02',
        'branch_id': 'MAIN_STORE',
        'terminal_id': 'POS-02',
        'grand_total': 250.0,
        'sub_total': 250.0,
        'payment_mode': 'UPI',
        'is_deleted': 0,
      });

      final results = await Future.wait([
        http.post(Uri.parse('$supabaseUrl/rest/v1/sales_invoices'), headers: headers, body: pos1Payload),
        http.post(Uri.parse('$supabaseUrl/rest/v1/sales_invoices'), headers: headers, body: pos2Payload),
      ]);

      // ignore: avoid_print
      print('POS-01 Sale Status: ${results[0].statusCode}');
      // ignore: avoid_print
      print('POS-02 Sale Status: ${results[1].statusCode}');

      final has201 = results[0].statusCode == 201 || results[1].statusCode == 201;
      expect(has201, isTrue, reason: 'At least one sale invoice POST must succeed.');

      // Cleanup
      await http.delete(
        Uri.parse('$supabaseUrl/rest/v1/sales_invoices?invoice_no=eq.$testInvNo'),
        headers: headers,
      );
    });

    test('Simultaneous Stock Adjustment Save from 2 Counters', () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testAdjNo = 'TEST_ADJ_$timestamp';

      final payload1 = jsonEncode({
        'entry_no': testAdjNo,
        'date': DateTime.now().toIso8601String(),
        'reason': 'Damaged Stock Check POS-01',
        'branch_id': 'MAIN_STORE',
        'terminal_id': 'POS-01',
      });

      final payload2 = jsonEncode({
        'entry_no': testAdjNo,
        'date': DateTime.now().toIso8601String(),
        'reason': 'Damaged Stock Check POS-02',
        'branch_id': 'MAIN_STORE',
        'terminal_id': 'POS-02',
      });

      final results = await Future.wait([
        http.post(Uri.parse('$supabaseUrl/rest/v1/stock_adjustments'), headers: headers, body: payload1),
        http.post(Uri.parse('$supabaseUrl/rest/v1/stock_adjustments'), headers: headers, body: payload2),
      ]);

      // ignore: avoid_print
      print('POS-01 Adj Status: ${results[0].statusCode}');
      // ignore: avoid_print
      print('POS-02 Adj Status: ${results[1].statusCode}');

      final has201 = results[0].statusCode == 201 || results[1].statusCode == 201;
      expect(has201, isTrue, reason: 'At least one stock adjustment POST must succeed.');

      // Cleanup
      await http.delete(
        Uri.parse('$supabaseUrl/rest/v1/stock_adjustments?entry_no=eq.$testAdjNo'),
        headers: headers,
      );
    });
  });
}
