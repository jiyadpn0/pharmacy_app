import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Pillar 12 & Full-System Static Diagnostics Test', () {
    test('sales_draft_service.dart and related widgets exist and are non-empty', () {
      final serviceFile = File('lib/services/sales_draft_service.dart');
      expect(serviceFile.existsSync(), isTrue);
      expect(serviceFile.lengthSync(), greaterThan(100));

      final bannerFile = File('lib/widgets/sales/sales_draft_recovery_banner.dart');
      expect(bannerFile.existsSync(), isTrue);
      expect(bannerFile.lengthSync(), greaterThan(100));
    });

    test('All 12 Core Operational Pillar Services exist in codebase', () {
      final requiredFiles = [
        'lib/services/supplier_ledger_service.dart',      // Pillar 1
        'lib/services/customer_ledger_service.dart',      // Pillar 2
        'lib/services/schedule_h1_register_service.dart', // Pillar 4
        'lib/services/lan_sync_service.dart',             // Pillar 5
        'lib/services/day_closing_service.dart',          // Pillar 6
        'lib/services/gst_report_service.dart',           // Pillar 7
        'lib/utils/app_validators.dart',                  // Pillar 8
        'lib/services/clinical_interaction_service.dart', // Pillar 10
        'lib/services/print_spooler_service.dart',        // Pillar 10
        'lib/services/database_maintenance_service.dart', // Pillar 11
        'lib/services/sales_draft_service.dart',          // Pillar 12
      ];

      for (final p in requiredFiles) {
        final f = File(p);
        expect(f.existsSync(), isTrue, reason: 'Expected $p to exist.');
      }
    });
  });
}
