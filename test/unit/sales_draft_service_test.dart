import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_app/models/erp_models.dart';
import 'package:pharmacy_app/services/sales_draft_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SalesDraftService.instance.clearDraft();
  });

  group('Pillar 12: SalesDraftService Crash Recovery Tests', () {
    test('saveDraft and checkUncommittedDraft preserve full billing context', () async {
      final product = Product(
        id: 'PROD_AZITHRO',
        name: 'Azithromycin 500mg',
        batch: 'AZ-101',
        expiry: '2027-08',
        mrp: 120.0,
        purchaseRate: 80.0,
        salePrice: 110.0,
        packSize: 10,
        gstPercent: 12.0,
        rack: 'R1-B2',
      );

      final item = SaleItem(
        product: product,
        qty: 2,
        looseQty: 3,
        fQty: 1,
        packin: 10,
        mrp: 120.0,
        sRate: 110.0,
        discPercent: 5.0,
        discAmt: 11.0,
        gstPercent: 12.0,
        gstAmt: 25.08,
        total: 234.08,
        profit: 60.0,
        purchaseRate: 80.0,
        landingCost: 80.0,
      );

      final draft = SalesDraft(
        workspaceIndex: 0,
        agent: 'AG-01',
        customerAcc: 'Hospital Credit A/C',
        patient: 'John Doe',
        mobile: '9876543210',
        doctor: 'Dr. Sharma (REG-12345)',
        taxType: 2,
        orderType: 0,
        footerDiscPct: 2.5,
        footerDiscAmt: 5.85,
        otherChargesPct: 0.0,
        otherChargesAmt: 10.0,
        rcvdAmt: 250.0,
        paymentMode: 'Cash',
        remarks: 'Emergency Ward Dispense',
        focusRow: 1,
        focusCol: 3,
        items: [item],
      );

      await SalesDraftService.instance.saveDraft(draft);

      final recovered = await SalesDraftService.instance.checkUncommittedDraft();

      expect(recovered, isNotNull);
      expect(recovered!.items.length, equals(1));
      expect(recovered.customerAcc, equals('Hospital Credit A/C'));
      expect(recovered.patient, equals('John Doe'));
      expect(recovered.mobile, equals('9876543210'));
      expect(recovered.doctor, equals('Dr. Sharma (REG-12345)'));
      expect(recovered.footerDiscPct, equals(2.5));
      expect(recovered.footerDiscAmt, equals(5.85));
      expect(recovered.otherChargesAmt, equals(10.0));
      expect(recovered.rcvdAmt, equals(250.0));
      expect(recovered.paymentMode, equals('Cash'));
      expect(recovered.remarks, equals('Emergency Ward Dispense'));

      // Verify line item specifics
      final recoveredItem = recovered.items.first;
      expect(recoveredItem.product.name, equals('Azithromycin 500mg'));
      expect(recoveredItem.product.batch, equals('AZ-101'));
      expect(recoveredItem.product.expiry, equals('2027-08'));
      expect(recoveredItem.qty, equals(2));
      expect(recoveredItem.looseQty, equals(3));
      expect(recoveredItem.fQty, equals(1));
      expect(recoveredItem.discPercent, equals(5.0));
      expect(recoveredItem.mrp, equals(120.0));
      expect(recoveredItem.sRate, equals(110.0));
    });

    test('clearDraft completely purges persisted state', () async {
      final draft = SalesDraft(
        items: [
          SaleItem(
            product: Product(id: 'P1', name: 'Paracetamol', batch: 'B1', expiry: '2026-12'),
            qty: 1,
            total: 20.0,
          ),
        ],
      );

      await SalesDraftService.instance.saveDraft(draft);
      var recovered = await SalesDraftService.instance.checkUncommittedDraft();
      expect(recovered, isNotNull);

      await SalesDraftService.instance.clearDraft();
      recovered = await SalesDraftService.instance.checkUncommittedDraft();
      expect(recovered, isNull);
      expect(SalesDraftService.instance.hasPendingRecovery, isFalse);
    });

    test('acknowledgeRecovery hides pending recovery notice without wiping disk', () async {
      final draft = SalesDraft(
        items: [
          SaleItem(
            product: Product(id: 'P2', name: 'Ibuprofen', batch: 'B2', expiry: '2027-01'),
            qty: 2,
            total: 50.0,
          ),
        ],
      );

      await SalesDraftService.instance.saveDraft(draft);
      await SalesDraftService.instance.checkUncommittedDraft();
      expect(SalesDraftService.instance.hasPendingRecovery, isTrue);

      SalesDraftService.instance.acknowledgeRecovery();
      expect(SalesDraftService.instance.hasPendingRecovery, isFalse);
    });
  });
}
