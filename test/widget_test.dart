import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/main.dart';
import 'package:pharmacy_app/providers/app_provider.dart';
import 'package:pharmacy_app/providers/pharmacy_provider.dart';
import 'package:pharmacy_app/providers/master_data_provider.dart';
import 'package:pharmacy_app/providers/inventory_provider.dart';
import 'package:pharmacy_app/providers/mdi_controller.dart';
import 'package:pharmacy_app/controllers/sales_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(create: (_) => PharmacyProvider()),
          ChangeNotifierProvider(create: (_) => MasterDataProvider()),
          ChangeNotifierProvider(create: (_) => InventoryProvider()),
          ChangeNotifierProvider(create: (_) => MdiController()),
          ChangeNotifierProvider(create: (_) => SalesController()),
        ],
        child: const PharmacyApp(),
      ),
    );
    // The app intentionally keeps sync animations/timers active; dispose without waiting for settle.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
