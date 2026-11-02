# 🔧 How to Fix Every Issue — Step by Step Guide

> Each fix below includes **before/after code**, difficulty rating, and estimated time.

---

## 🔴 PHASE 1 — SAFETY FIXES (Do This Week)

---

### Fix #13: Operator Precedence Bug in Model Parsing ⚡ MOST URGENT

**Difficulty:** Easy | **Time:** 1-2 hours | **Risk if ignored:** Wrong prices, GST, stock values

**The Bug:**
```dart
// ❌ CURRENT — 'as num?' only casts map['gstPercent'], NOT the ?? result
gstPercent: (map['gst_percent'] ?? map['gstPercent'] as num?)?.toDouble() ?? 12.0,

// Dart sees this as:
gstPercent: (map['gst_percent'] ?? (map['gstPercent'] as num?))?.toDouble() ?? 12.0,
// If map['gst_percent'] exists but is a String like "5", the .toDouble() will CRASH
```

**The Fix — Option A (Quick):** Add parentheses around the `??` chain:
```dart
// ✅ FIXED
gstPercent: ((map['gst_percent'] ?? map['gstPercent']) as num?)?.toDouble() ?? 12.0,
```

**The Fix — Option B (Best):** Add a reusable helper at the top of `erp_models.dart`:
```dart
// Add this helper function at the top of the file
double _dbl(Map<String, dynamic> m, List<String> keys, [double def = 0.0]) {
  for (final k in keys) {
    final v = m[k];
    if (v == null) continue;
    if (v is num) return v.toDouble();
    if (v is String) {
      final parsed = double.tryParse(v);
      if (parsed != null) return parsed;
    }
  }
  return def;
}

int _integer(Map<String, dynamic> m, List<String> keys, [int def = 0]) {
  for (final k in keys) {
    final v = m[k];
    if (v == null) continue;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed;
    }
  }
  return def;
}

String _str(Map<String, dynamic> m, List<String> keys, [String def = '']) {
  for (final k in keys) {
    final v = m[k];
    if (v != null) return v.toString();
  }
  return def;
}
```

**Then replace ALL occurrences like:**
```dart
// ❌ Before
gstPercent: (map['gst_percent'] ?? map['gstPercent'] as num?)?.toDouble() ?? 12.0,
purchaseRate: (map['purchase_rate'] ?? map['purchaseRate'] as num?)?.toDouble() ?? 0.0,
saleRate: (map['sale_rate'] ?? map['saleRate'] ?? map['selling_rate'] as num?)?.toDouble() ?? 0.0,

// ✅ After
gstPercent: _dbl(map, ['gst_percent', 'gstPercent'], 12.0),
purchaseRate: _dbl(map, ['purchase_rate', 'purchaseRate']),
saleRate: _dbl(map, ['sale_rate', 'saleRate', 'selling_rate']),
```

**Lines to fix:** ~40+ occurrences in `erp_models.dart` (lines 116, 200-207, 476-492, 700-733, etc.)

**Ask me:** "Fix the precedence bug" and I'll do all 40+ automatically.

---

### Fix #9: Missing `mounted` Checks

**Difficulty:** Easy | **Time:** 2-3 hours | **Risk if ignored:** Runtime crashes

**The Pattern to Find & Fix:**
```dart
// ❌ Before — crashes if user navigates away during await
Future<void> _loadData() async {
  final data = await someAsyncCall();
  setState(() {
    _items = data;
  });
}

// ✅ After
Future<void> _loadData() async {
  final data = await someAsyncCall();
  if (!mounted) return;  // ← ADD THIS LINE
  setState(() {
    _items = data;
  });
}
```

**Where to add:** Every screen file in `lib/screens/` — after EVERY `await` that's followed by `setState()`, `showDialog()`, `Navigator.push()`, or `ScaffoldMessenger`.

**Ask me:** "Add mounted checks to sales_screen.dart" (one file at a time).

---

### Fix #6: SQL Injection in Chronic Refill Service

**Difficulty:** Easy | **Time:** 15 minutes | **Risk if ignored:** Security vulnerability

```dart
// ❌ Before — string interpolation in SQL
final query = '''
  SELECT ...
  FROM sales_invoices si
  JOIN sales_items sitem ON si.entry_no = sitem.invoice_no
  WHERE si.date >= '$date35DaysAgo' AND si.date <= '$date20DaysAgo'
''';
final rows = await db.rawQuery(query);

// ✅ After — parameterized query
final query = '''
  SELECT ...
  FROM sales_invoices si
  JOIN sales_items sitem ON si.entry_no = sitem.invoice_no
  WHERE si.date >= ? AND si.date <= ?
''';
final rows = await db.rawQuery(query, [date35DaysAgo, date20DaysAgo]);
```

**Ask me:** "Fix the SQL injection" and I'll do it now.

---

### Fix #5: Hardcoded Security Salt

**Difficulty:** Medium | **Time:** 30 minutes | **Risk if ignored:** PIN can be cracked

```dart
// ❌ Before
class SecurityCrypto {
  static const String _saltKey = "PHARMAPRO_SALT_KEY";  // Hardcoded!

  static String hashPin(String plainPin) {
    final bytes = utf8.encode(plainPin + _saltKey);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

// ✅ After — per-user random salt
import 'dart:math';

class SecurityCrypto {
  static String _generateSalt([int length = 32]) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Returns "salt:hash" format
  static String hashPin(String plainPin, {String? existingSalt}) {
    final salt = existingSalt ?? _generateSalt();
    final bytes = utf8.encode(plainPin + salt);
    final digest = sha256.convert(bytes);
    return '$salt:${digest.toString()}';
  }

  static bool verifyPin(String inputPin, String storedValue) {
    if (storedValue.isEmpty || !storedValue.contains(':')) return false;
    final parts = storedValue.split(':');
    final salt = parts[0];
    final expectedHash = parts[1];
    final inputHash = hashPin(inputPin, existingSalt: salt);
    return inputHash.split(':')[1] == expectedHash;
  }
}
```

> ⚠️ This is a breaking change — existing stored PINs won't verify. You'll need a one-time migration that prompts users to re-set their PIN.

---

## 🟠 PHASE 2 — ARCHITECTURE FIXES (Next 2-4 Weeks)

---

### Fix #1: Split pharmacy_provider.dart (17,400 lines → 8-10 files)

**Difficulty:** Hard | **Time:** 3-5 days | **Risk if ignored:** Unmaintainable, slow rebuilds

**Step-by-step approach:**

**Step 1:** Identify logical domains in the provider:
```
pharmacy_provider.dart (17,400 lines) → Split into:
├── providers/sales_provider.dart        (~2,000 lines)
├── providers/purchase_provider.dart     (~2,000 lines)
├── providers/stock_provider.dart        (~1,500 lines)
├── providers/customer_provider.dart     (~800 lines)
├── providers/return_provider.dart       (~1,500 lines)
├── providers/gst_provider.dart          (~1,000 lines)
├── providers/report_provider.dart       (~1,200 lines)
├── providers/settings_provider.dart     (~800 lines)
├── providers/sync_state_provider.dart   (~500 lines)
└── providers/pharmacy_provider.dart     (~1,000 lines) ← slim coordinator
```

**Step 2:** Start with the EASIEST extraction — move GST/report methods first:
```dart
// NEW FILE: lib/providers/gst_provider.dart
class GstProvider extends ChangeNotifier {
  // Move all GST calculation, GSTR-1, GSTR-2B methods here
  // Move all GST report generation here
}
```

**Step 3:** In `main.dart`, register all providers:
```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => PharmacyProvider()),
    ChangeNotifierProvider(create: (_) => SalesProvider()),
    ChangeNotifierProvider(create: (_) => PurchaseProvider()),
    ChangeNotifierProvider(create: (_) => StockProvider()),
    ChangeNotifierProvider(create: (_) => GstProvider()),
    // ... etc
  ],
  child: MyApp(),
)
```

**Step 4:** Update screens to use specific providers:
```dart
// ❌ Before — rebuilds on ANY change
final pharma = context.watch<PharmacyProvider>();

// ✅ After — rebuilds only on sales changes
final sales = context.watch<SalesProvider>();
```

**Ask me:** "Extract GST methods from pharmacy_provider" — I'll do one domain at a time.

---

### Fix #2: Split Monster Screens (sales_screen.dart = 12,181 lines)

**Difficulty:** Medium | **Time:** 1-2 days per screen

**Strategy — Extract widgets bottom-up:**
```
sales_screen.dart (12,181 lines) → Split into:
├── screens/sales_screen.dart                  (~500 lines) ← main scaffold
├── widgets/sales/sales_item_table.dart         (~800 lines)
├── widgets/sales/sales_header_bar.dart         (~300 lines)
├── widgets/sales/sales_product_search.dart     (~400 lines)
├── widgets/sales/sales_totals_panel.dart       (~300 lines)
├── widgets/sales/sales_payment_section.dart    (~400 lines)
├── widgets/sales/sales_batch_selector.dart     (~300 lines)
├── widgets/sales/sales_discount_dialog.dart    (~200 lines)
├── widgets/sales/sales_customer_panel.dart     (~300 lines)
└── widgets/sales/sales_action_buttons.dart     (~200 lines)
```

**How to extract:**
```dart
// 1. Find a self-contained build section (e.g., the totals panel)
// 2. Cut it into a new StatelessWidget
// 3. Pass dependencies as constructor parameters

// NEW FILE: lib/widgets/sales/sales_totals_panel.dart
class SalesTotalsPanel extends StatelessWidget {
  final double subtotal;
  final double gstAmount;
  final double discount;
  final double netAmount;

  const SalesTotalsPanel({
    super.key,
    required this.subtotal,
    required this.gstAmount,
    required this.discount,
    required this.netAmount,
  });

  @override
  Widget build(BuildContext context) {
    // Move the totals panel build code here
  }
}
```

---

### Fix #4: Structured Error Handling

**Difficulty:** Medium | **Time:** 2-3 days

**Step 1:** Create a Result type:
```dart
// NEW FILE: lib/utils/result.dart
sealed class Result<T> {
  const Result();
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

class Failure<T> extends Result<T> {
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  const Failure(this.message, {this.error, this.stackTrace});
}
```

**Step 2:** Refactor critical methods:
```dart
// ❌ Before
Future<void> saveSale(SaleInvoice invoice) async {
  try {
    await db.insert(...);
  } catch (e) {
    debugPrint("Error: $e");  // Silently swallowed!
  }
}

// ✅ After
Future<Result<String>> saveSale(SaleInvoice invoice) async {
  try {
    await db.insert(...);
    return const Success("Invoice saved");
  } catch (e, stack) {
    AppLogger.error("saveSale failed", error: e, stackTrace: stack);
    return Failure("Failed to save invoice: ${e.toString()}", error: e, stackTrace: stack);
  }
}

// In the screen:
final result = await provider.saveSale(invoice);
if (result is Failure) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(result.message), backgroundColor: Colors.red),
  );
}
```

---

### Fix #8: Split Supabase Sync Service (7,339 lines)

**Strategy:**
```
supabase_sync_service.dart (7,339 lines) → Split into:
├── services/sync/sync_coordinator.dart        (~500 lines) ← orchestrator
├── services/sync/product_sync_handler.dart    (~800 lines)
├── services/sync/sales_sync_handler.dart      (~800 lines)
├── services/sync/purchase_sync_handler.dart   (~800 lines)
├── services/sync/stock_sync_handler.dart      (~600 lines)
├── services/sync/return_sync_handler.dart     (~600 lines)
├── services/sync/customer_sync_handler.dart   (~400 lines)
├── services/sync/sync_conflict_resolver.dart  (~400 lines)
└── services/sync/sync_queue_manager.dart      (~300 lines)
```

---

## 🟡 PHASE 3 — QUALITY IMPROVEMENTS (Ongoing)

---

### Fix #3: Add Unit Tests

**Priority test files to create:**
```
test/
├── unit/
│   ├── tax_calculator_test.dart         ← EXPAND (exists)
│   ├── invoice_total_test.dart          ← NEW
│   ├── gst_calculation_test.dart        ← NEW
│   ├── stock_adjustment_test.dart       ← NEW
│   ├── model_parsing_test.dart          ← NEW (test the _dbl helper!)
│   ├── security_crypto_test.dart        ← NEW
│   └── demand_forecasting_test.dart     ← NEW
├── integration/
│   ├── sale_flow_test.dart              ← NEW
│   └── sync_service_test.dart           ← NEW
```

**Example test:**
```dart
// test/unit/model_parsing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/erp_models.dart';

void main() {
  group('Product.fromMap', () {
    test('parses gst_percent as int', () {
      final product = Product.fromMap({'gst_percent': 18, 'name': 'Test'});
      expect(product.gstPercent, 18.0);
    });

    test('falls back to gstPercent key', () {
      final product = Product.fromMap({'gstPercent': 5, 'name': 'Test'});
      expect(product.gstPercent, 5.0);
    });

    test('defaults to 12.0 when missing', () {
      final product = Product.fromMap({'name': 'Test'});
      expect(product.gstPercent, 12.0);
    });

    test('handles string numeric values', () {
      final product = Product.fromMap({'gst_percent': '28', 'name': 'Test'});
      expect(product.gstPercent, 28.0);
    });
  });
}
```

---

### Fix #10: Rename Cloud Backup or Add Real Cloud

**Quick rename fix:**
```dart
// Rename file: cloud_backup_service.dart → local_backup_service.dart
// Rename class: CloudBackupService → LocalBackupService
// Update all imports
```

**Or add real cloud backup to Supabase Storage:**
```dart
Future<String?> uploadToSupabaseStorage(File backupFile) async {
  try {
    final fileName = path.basename(backupFile.path);
    final bytes = await backupFile.readAsBytes();
    await Supabase.instance.client.storage
        .from('backups')
        .uploadBinary(fileName, bytes);
    return fileName;
  } catch (e) {
    debugPrint("Cloud Upload Error: $e");
    return null;
  }
}
```

---

### Fix #12: Merge WhatsApp Services

```dart
// DELETE: whatsapp_notification_service.dart
// MOVE its methods INTO: whatsapp_service.dart
// Add sendDigitalInvoice() and sendRefillReminder() to WhatsAppService
```

---

## 🔵 PHASE 4 — POLISH (Future Sprints)

### Fix #21: Add Dependency Injection
```yaml
# Add to pubspec.yaml
dependencies:
  get_it: ^7.6.0
```

```dart
// lib/di/service_locator.dart
import 'package:get_it/get_it.dart';

final getIt = GetIt.instance;

void setupServiceLocator() {
  getIt.registerLazySingleton(() => DbHelper.instance);
  getIt.registerLazySingleton(() => SupabaseSyncService.instance);
  getIt.registerLazySingleton(() => RankingEngineService.instance);
  // ... etc
}
```

### Fix #24: Add CI/CD
```yaml
# .github/workflows/flutter.yml
name: Flutter CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
```

---

## 🎯 Quick Reference — "Ask Me To Fix" Commands

| Command | What I'll Do | Time |
|:--------|:-------------|:-----|
| "Fix the precedence bug" | Fix all 40+ `as num?` casts in `erp_models.dart` | 10 min |
| "Fix the SQL injection" | Parameterize `chronic_refill_service.dart` query | 5 min |
| "Fix security crypto" | Add per-user random salts | 10 min |
| "Merge WhatsApp services" | Consolidate into one service | 15 min |
| "Add mounted checks to [screen]" | Add `if (!mounted) return;` to one screen | 15 min |
| "Create model parsing tests" | Write unit tests for `erp_models.dart` | 15 min |
| "Extract [section] from sales_screen" | Pull out a widget into its own file | 20 min |
| "Split GST methods from provider" | Create `GstProvider` with moved methods | 30 min |
| "Add Result type" | Create `Result<T>` and refactor one method | 15 min |
