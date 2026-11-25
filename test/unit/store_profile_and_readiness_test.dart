import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_app/models/erp_models.dart';
import 'package:pharmacy_app/utils/app_validators.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Pre-Release Readiness & Store Profile Compliance Tests', () {
    test('CompanyProfile correctly serializes Drug License Form 20/21 and GSTIN', () {
      final profile = CompanyProfile(
        name: 'Sahakar Medicals & Surgicals',
        address: 'Main Road, Kalpetta, Wayanad, Kerala - 673121',
        phone: '9847012345',
        gstIn: '32AABCS1429B1Z1',
        dlNumber: 'KL-WAY-145290 / KL-WAY-145291',
        tagline: 'Trusted Healthcare & Genuine Medicines',
      );

      final map = profile.toMap();
      expect(map['name'], equals('Sahakar Medicals & Surgicals'));
      expect(map['gst_in'], equals('32AABCS1429B1Z1'));
      expect(map['dl_number'], equals('KL-WAY-145290 / KL-WAY-145291'));
      expect(map['tagline'], equals('Trusted Healthcare & Genuine Medicines'));

      // Validate statutory compliance formats
      expect(AppValidators.isValidGstin(profile.gstIn), isTrue);
      expect(AppValidators.isValidPhone(profile.phone), isTrue);
      expect(AppValidators.isValidDrugLicense(profile.dlNumber), isTrue);
    });

    test('Preferred printer and secondary USB backup paths persist cleanly in SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();

      // Set USB mirror destination
      await prefs.setString('secondary_backup_path', 'E:\\Pharmacy_Daily_Backups');
      expect(prefs.getString('secondary_backup_path'), equals('E:\\Pharmacy_Daily_Backups'));

      // Set Preferred thermal receipt printer
      await prefs.setString('preferred_printer_name', 'TVS RP 3200 Star');
      expect(prefs.getString('preferred_printer_name'), equals('TVS RP 3200 Star'));

      // Set Backup retention
      await prefs.setInt('backup_retention_days', 45);
      expect(prefs.getInt('backup_retention_days'), equals(45));
    });
  });
}
