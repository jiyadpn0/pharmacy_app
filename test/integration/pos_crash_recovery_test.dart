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

  group('Pillar 12: Offline-First Cart Auto-Recovery on Power Cut / Crash Tests', () {
    test('Simulate mid-billing abrupt power cut: auto-saved draft restores entire cart state intact', () async {
      // 1. Setup multi-item cart with diverse batch allocations, expiries, rates, and discounts
      final p1 = Product(
        id: 'PROD_AMOX_500',
        name: 'Amoxicillin 500mg Capsules',
        batch: 'AMX-2026',
        expiry: '2027-11',
        mrp: 150.0,
        purchaseRate: 95.0,
        salePrice: 140.0,
        packSize: 10,
        gstPercent: 12.0,
        rack: 'RACK-A3',
      );

      final p2 = Product(
        id: 'PROD_CETRIZINE',
        name: 'Cetirizine 10mg Tablets',
        batch: 'CTZ-991',
        expiry: '2028-02',
        mrp: 45.0,
        purchaseRate: 20.0,
        salePrice: 40.0,
        packSize: 10,
        gstPercent: 12.0,
        rack: 'RACK-B1',
      );

      final item1 = SaleItem(
        product: p1,
        qty: 3,
        looseQty: 5,
        fQty: 1,
        packin: 10,
        mrp: 150.0,
        sRate: 140.0,
        discPercent: 10.0,
        discAmt: 42.0,
        gstPercent: 12.0,
        gstAmt: 45.36,
        total: 423.36,
        profit: 135.0,
        purchaseRate: 95.0,
        landingCost: 95.0,
      );

      final item2 = SaleItem(
        product: p2,
        qty: 1,
        looseQty: 0,
        fQty: 0,
        packin: 10,
        mrp: 45.0,
        sRate: 40.0,
        discPercent: 0.0,
        discAmt: 0.0,
        gstPercent: 12.0,
        gstAmt: 4.8,
        total: 44.8,
        profit: 20.0,
        purchaseRate: 20.0,
        landingCost: 20.0,
      );

      // 2. Billing session with doctor, patient, and footer discounts
      final draftAtCrash = SalesDraft(
        workspaceIndex: 1,
        agent: 'AG-MAIN',
        customerAcc: 'MediCare Insurance TPA',
        patient: 'Ramesh Patel',
        mobile: '9825012345',
        doctor: 'Dr. V. K. Mehta (REG-GMC-4491)',
        taxType: 2,
        orderType: 0,
        footerDiscPct: 5.0,
        footerDiscAmt: 23.4,
        otherChargesPct: 0.0,
        otherChargesAmt: 15.0,
        rcvdAmt: 500.0,
        paymentMode: 'UPI',
        remarks: 'Emergency OPD Dispense',
        focusRow: 2,
        focusCol: 1,
        savedAt: DateTime(2026, 11, 24, 18, 45, 0),
        items: [item1, item2],
      );

      // 3. Auto-save runs periodic flush to persistent storage
      await SalesDraftService.instance.saveDraft(draftAtCrash);

      // 4. Simulate computer reboot: fresh checkUncommittedDraft() on app launch
      final recoveredDraft = await SalesDraftService.instance.checkUncommittedDraft();

      expect(recoveredDraft, isNotNull);
      expect(SalesDraftService.instance.hasPendingRecovery, isTrue);

      // 5. Verify patient & doctor metadata integrity
      expect(recoveredDraft!.patient, equals('Ramesh Patel'));
      expect(recoveredDraft.mobile, equals('9825012345'));
      expect(recoveredDraft.doctor, equals('Dr. V. K. Mehta (REG-GMC-4491)'));
      expect(recoveredDraft.customerAcc, equals('MediCare Insurance TPA'));
      expect(recoveredDraft.paymentMode, equals('UPI'));
      expect(recoveredDraft.remarks, equals('Emergency OPD Dispense'));
      expect(recoveredDraft.workspaceIndex, equals(1));

      // 6. Verify footer financial context
      expect(recoveredDraft.footerDiscPct, equals(5.0));
      expect(recoveredDraft.footerDiscAmt, equals(23.4));
      expect(recoveredDraft.otherChargesAmt, equals(15.0));
      expect(recoveredDraft.rcvdAmt, equals(500.0));

      // 7. Verify inventory line items and FEFO batch details
      expect(recoveredDraft.items.length, equals(2));
      final recovered1 = recoveredDraft.items[0];
      expect(recovered1.product.name, equals('Amoxicillin 500mg Capsules'));
      expect(recovered1.product.batch, equals('AMX-2026'));
      expect(recovered1.product.expiry, equals('2027-11'));
      expect(recovered1.qty, equals(3));
      expect(recovered1.looseQty, equals(5));
      expect(recovered1.fQty, equals(1));
      expect(recovered1.discPercent, equals(10.0));
      expect(recovered1.total, equals(423.36));

      final recovered2 = recoveredDraft.items[1];
      expect(recovered2.product.name, equals('Cetirizine 10mg Tablets'));
      expect(recovered2.product.batch, equals('CTZ-991'));
      expect(recovered2.qty, equals(1));
      expect(recovered2.looseQty, equals(0));
      expect(recovered2.total, equals(44.8));

      // 8. Test Discard workflow: clearing purges persistent storage
      await SalesDraftService.instance.clearDraft();
      final afterDiscard = await SalesDraftService.instance.checkUncommittedDraft();
      expect(afterDiscard, isNull);
      expect(SalesDraftService.instance.hasPendingRecovery, isFalse);
    });

    test('Empty cart never triggers recovery alert', () async {
      final emptyDraft = SalesDraft(items: []);
      await SalesDraftService.instance.saveDraft(emptyDraft);

      final recovered = await SalesDraftService.instance.checkUncommittedDraft();
      expect(recovered, isNull);
      expect(SalesDraftService.instance.hasPendingRecovery, isFalse);
    });
  });
}
