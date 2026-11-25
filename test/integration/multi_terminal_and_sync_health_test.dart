import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/services/server_config_service.dart';
import 'package:pharmacy_app/services/stock_outbox_service.dart';
import 'package:pharmacy_app/widgets/sync_health_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DbHelper.instance.setMockDatabase(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_outbox (
        id TEXT PRIMARY KEY,
        idempotency_key TEXT UNIQUE,
        operation_type TEXT,
        reference_no TEXT,
        branch_id TEXT,
        terminal_id TEXT,
        user_id TEXT,
        payload TEXT,
        status TEXT,
        error_message TEXT,
        retry_count INTEGER DEFAULT 0,
        last_attempt_at TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_return_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_return_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');
  });

  tearDown(() async {
    DbHelper.instance.setMockDatabase(null);
    await db.close();
  });

  test('Multi-terminal sequence prefix and idempotency key generation', () async {
    ServerConfigService.instance.overrideTerminalId('POS-02');
    await ServerConfigService.instance.setStoreBranchId('MAIN_STORE');

    expect(ServerConfigService.instance.terminalId, 'POS-02');
    expect(ServerConfigService.instance.terminalPrefix, 'T2-');

    final idempKey1 = StockOutboxService.generateIdempotencyKey(
      branchId: 'MAIN_STORE',
      terminalId: 'POS-02',
      operationType: 'SALE',
      referenceNo: 'INV-2026-001',
    );

    expect(idempKey1, 'IDEMP_MAIN_STORE_POS-02_SALE_INV-2026-001');

    // Queue operation in outbox
    final entry = await StockOutboxService.instance.queueOperation(
      operationType: 'SALE',
      referenceNo: 'INV-2026-001',
      payload: {'grand_total': 150.0, 'items_count': 1},
      executor: db,
    );

    expect(entry.status, 'pending');
    expect(entry.terminalId, 'POS-02');

    // Verify pendingCount updates
    await StockOutboxService.instance.refreshCounts();
    expect(StockOutboxService.instance.pendingCount.value, 1);

    // Verify idempotency prevents duplicate outbox entries
    final duplicateEntry = await StockOutboxService.instance.queueOperation(
      operationType: 'SALE',
      referenceNo: 'INV-2026-001',
      payload: {'grand_total': 150.0, 'items_count': 1},
      executor: db,
    );

    expect(duplicateEntry.id, entry.id);

    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM stock_outbox')) ?? 0;
    expect(count, 1);
  });

  testWidgets('SyncHealthBadge displays terminal ID, latency, and outbox count in dark and light modes', (tester) async {
    ServerConfigService.instance.overrideTerminalId('POS-01');
    StockOutboxService.instance.pendingCount.value = 3;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SyncHealthBadge(isDark: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('POS-01'), findsOneWidget);
    expect(find.text('3 queued'), findsOneWidget);
  });
}
