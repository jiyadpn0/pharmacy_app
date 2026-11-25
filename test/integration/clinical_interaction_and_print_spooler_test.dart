import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/erp_models.dart';
import 'package:pharmacy_app/services/clinical_interaction_service.dart';
import 'package:pharmacy_app/services/print_spooler_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pillar 10: Clinical Interaction Engine Tests', () {
    test('evaluateInteractions detects severe and moderate clinical drug combinations', () {
      final service = ClinicalInteractionService.instance;

      // Basket 1: Warfarin + Aspirin (Major Hemorrhage Risk)
      final basket1 = [
        SaleItem(
          product: Product(id: '1', name: 'WARFARIN 5MG', genericName: 'Warfarin Sodium', batch: 'W1', expiry: '05/27'),
          qty: 10,
        ),
        SaleItem(
          product: Product(id: '2', name: 'ASPIRIN 75MG', genericName: 'Acetylsalicylic Acid', batch: 'A1', expiry: '05/27'),
          qty: 14,
        ),
      ];

      final warnings1 = service.evaluateInteractions(basket1);
      expect(warnings1.length, equals(1));
      expect(warnings1.first.severity, equals(InteractionSeverity.severe));
      expect(warnings1.first.title, contains('Bleeding'));
      expect(service.hasSevereInteractions(basket1), isTrue);

      // Basket 2: Sildenafil + Nitroglycerin (Profound Hypotension Risk)
      final basket2 = [
        SaleItem(
          product: Product(id: '3', name: 'SILDA 50', genericName: 'Sildenafil Citrate', batch: 'S1', expiry: '05/27'),
          qty: 4,
        ),
        SaleItem(
          product: Product(id: '4', name: 'NITROCONTIN 2.6', genericName: 'Nitroglycerin Controlled Release', batch: 'N1', expiry: '05/27'),
          qty: 30,
        ),
      ];

      final warnings2 = service.evaluateInteractions(basket2);
      expect(warnings2.length, equals(1));
      expect(warnings2.first.severity, equals(InteractionSeverity.severe));
      expect(warnings2.first.title, contains('Hypotension'));

      // Basket 3: Atorvastatin + Clarithromycin (Rhabdomyolysis Risk)
      final basket3 = [
        SaleItem(
          product: Product(id: '5', name: 'ATORVA 20', genericName: 'Atorvastatin Calcium', batch: 'AT1', expiry: '05/27'),
          qty: 15,
        ),
        SaleItem(
          product: Product(id: '6', name: 'CLARIBID 500', genericName: 'Clarithromycin', batch: 'CL1', expiry: '05/27'),
          qty: 7,
        ),
      ];

      final warnings3 = service.evaluateInteractions(basket3);
      expect(warnings3.length, equals(1));
      expect(warnings3.first.severity, equals(InteractionSeverity.severe));
      expect(warnings3.first.title, contains('Rhabdomyolysis'));

      // Basket 4: Metoprolol + Verapamil (Severe Bradycardia / Heart Block Risk)
      final basket4 = [
        SaleItem(
          product: Product(id: '7', name: 'METOLAR 50', genericName: 'Metoprolol Tartrate', batch: 'M1', expiry: '05/27'),
          qty: 10,
        ),
        SaleItem(
          product: Product(id: '8', name: 'CALAPTIN 40', genericName: 'Verapamil Hydrochloride', batch: 'V1', expiry: '05/27'),
          qty: 10,
        ),
      ];

      final warnings4 = service.evaluateInteractions(basket4);
      expect(warnings4.length, equals(1));
      expect(warnings4.first.severity, equals(InteractionSeverity.severe));
      expect(warnings4.first.title, contains('Bradycardia'));

      // Basket 5: Safe Non-Interacting Common Combinations (Paracetamol + Amoxicillin)
      final safeBasket = [
        SaleItem(
          product: Product(id: '9', name: 'DOLO 650', genericName: 'Paracetamol', batch: 'D1', expiry: '05/27'),
          qty: 15,
        ),
        SaleItem(
          product: Product(id: '10', name: 'MOX 500', genericName: 'Amoxicillin Trihydrate', batch: 'MO1', expiry: '05/27'),
          qty: 10,
        ),
      ];

      final safeWarnings = service.evaluateInteractions(safeBasket);
      expect(safeWarnings.isEmpty, isTrue);
      expect(service.hasSevereInteractions(safeBasket), isFalse);
    });
  });

  group('Pillar 10: Resilient Print Spooler Queue Tests', () {
    tearDown(() {
      PrintSpoolerService.instance.clearFailedJobs();
      PrintSpoolerService.onPrintFailed = null;
    });

    test('enqueuePrintTask executes successful print jobs sequentially in background', () async {
      final executed = <String>[];
      final completer = Completer<void>();

      PrintSpoolerService.enqueuePrintTask(() async {
        executed.add('TASK_1');
      }, title: 'Job 1');

      PrintSpoolerService.enqueuePrintTask(() async {
        executed.add('TASK_2');
        completer.complete();
      }, title: 'Job 2');

      await completer.future;

      expect(executed, equals(['TASK_1', 'TASK_2']));
      expect(PrintSpoolerService.instance.hasFailedJobs, isFalse);
    });

    test('enqueuePrintTask retries transient errors and moves persistent failures to dead-letter queue', () async {
      int attempts = 0;
      PrintJob? reportedFailedJob;

      final failureCompleter = Completer<void>();
      PrintSpoolerService.onPrintFailed = (job) {
        reportedFailedJob = job;
        if (!failureCompleter.isCompleted) {
          failureCompleter.complete();
        }
      };

      PrintSpoolerService.enqueuePrintTask(
        () async {
          attempts++;
          throw Exception("SocketException: Printer offline or out of paper");
        },
        title: 'Thermal Bill #101',
        maxAttempts: 3,
      );

      await failureCompleter.future;

      // Must have attempted exactly 3 times before giving up
      expect(attempts, equals(3));
      expect(PrintSpoolerService.instance.hasFailedJobs, isTrue);
      expect(PrintSpoolerService.instance.failedJobs.length, equals(1));
      expect(reportedFailedJob, isNotNull);
      expect(reportedFailedJob!.title, equals('Thermal Bill #101'));
      expect(reportedFailedJob!.status, equals(PrintJobStatus.failed));
      expect(reportedFailedJob!.lastError, contains("Printer offline"));

      // Test operator retry mechanism
      bool recovered = false;
      final retryCompleter = Completer<void>();

      PrintSpoolerService.enqueuePrintTask(() async {
        recovered = true;
        retryCompleter.complete();
      }, title: 'Thermal Bill #101 (Retry)');

      await retryCompleter.future;
      expect(recovered, isTrue);

      // Clear dead-letter queue
      PrintSpoolerService.instance.clearFailedJobs();
      expect(PrintSpoolerService.instance.hasFailedJobs, isFalse);
    });
  });
}
