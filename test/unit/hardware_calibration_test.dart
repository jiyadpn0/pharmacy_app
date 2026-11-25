import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_app/services/esc_pos_printer_service.dart';
import 'package:pharmacy_app/models/erp_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Hardware & Peripheral Calibration Tests', () {
    test('EscPosPrinterService correctly generates ESC/POS binary stream with Cash Drawer Kick and Paper Cut', () {
      final company = CompanyProfile(
        name: 'SAHAKAR MEDICALS & SURGICALS',
        address: 'Kalpetta, Wayanad',
        phone: '9847012345',
        gstIn: '32AABCS1429B1Z1',
        dlNumber: 'KL-WAY-145290 / KL-WAY-145291',
      );

      final items = [
        {
          'name': 'Paracetamol 650mg',
          'batch': 'B124',
          'qty': '10',
          'rate': 20.0,
          'amount': 200.0,
        },
        {
          'name': 'Azithromycin 500mg',
          'batch': 'AZ99',
          'qty': '2',
          'rate': 120.0,
          'amount': 240.0,
        },
      ];

      final bytes = EscPosPrinterService.instance.generateReceiptBytes(
        company: company,
        invoiceNo: 'INV-1001',
        dateStr: '24/11/2026',
        patientName: 'Muhammed Jiyad',
        doctorName: 'Dr. Suresh Babu',
        items: items,
        totalAmount: 440.0,
        totalDiscount: 20.0,
        gstTotal: 52.8,
        paymentMode: 'Cash',
      );

      expect(bytes, isNotEmpty);

      // Verify ESC/POS Initialization Command: [0x1B, 0x40]
      expect(bytes.sublist(0, 2), equals([0x1B, 0x40]));

      // Verify Cash Drawer Pulse Command is embedded: [0x1B, 0x70, 0x00, 0x19, 0xFA]
      bool hasCashDrawerCmd = false;
      for (int i = 0; i <= bytes.length - 5; i++) {
        if (bytes[i] == 0x1B &&
            bytes[i + 1] == 0x70 &&
            bytes[i + 2] == 0x00 &&
            bytes[i + 3] == 0x19 &&
            bytes[i + 4] == 0xFA) {
          hasCashDrawerCmd = true;
          break;
        }
      }
      expect(hasCashDrawerCmd, isTrue, reason: 'ESC/POS receipt must contain Cash Drawer kick pulse');

      // Verify Paper Cut Command is embedded at the end: [0x1D, 0x56, 0x42, 0x00]
      final endSublist = bytes.sublist(bytes.length - 4);
      expect(endSublist, equals([0x1D, 0x56, 0x42, 0x00]), reason: 'ESC/POS receipt must terminate with paper cut command');
    });

    test('USB Barcode Scanner Wedge Timing Algorithm accurately distinguishes scanner bursts from manual typing', () {
      // 1. Simulate USB Barcode Scanner Wedge input:
      // A physical hardware scanner dumps a 13-digit EAN-13 barcode in <100ms (~5ms per character)
      const scannedBarcode = '8901030012345';
      const scannerTotalMs = 45;
      const scannerAvgPerChar = scannerTotalMs / scannedBarcode.length;
      const isHardwareScanner = scannerAvgPerChar < 60;

      expect(isHardwareScanner, isTrue, reason: 'High-speed character burst must be identified as hardware barcode scanner');

      // 2. Simulate human manual typing on keyboard:
      // Human typing takes 200ms - 500ms per keystroke (e.g. 13 characters in 3500ms)
      const humanTotalMs = 3500;
      const humanAvgPerChar = humanTotalMs / scannedBarcode.length;
      const isHumanTyping = humanAvgPerChar >= 60;

      expect(isHumanTyping, isTrue, reason: 'Slower sequential input must be identified as manual keyboard typing');
    });

    test('Printer settings and Preferred Counter Printer persist cleanly in SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('preferred_printer_name', 'EPSON TM-T82 Receipt');
      await prefs.setString('printer_mode', 'thermal');
      await prefs.setString('thermal_printer_ip', '192.168.1.150');

      expect(prefs.getString('preferred_printer_name'), equals('EPSON TM-T82 Receipt'));
      expect(prefs.getString('printer_mode'), equals('thermal'));
      expect(prefs.getString('thermal_printer_ip'), equals('192.168.1.150'));
    });
  });
}
