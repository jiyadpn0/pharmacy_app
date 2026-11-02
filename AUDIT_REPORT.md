# 🏥 Pharmacy ERP App — Full Codebase Audit Report

> **Version:** 3.3.7+1 | **Framework:** Flutter (Desktop) | **Date:** Nov 2, 2026

---

## 📊 Audit Summary

| Metric | Value |
|:---|:---|
| Total Dart Files (lib/) | ~100+ |
| Total Lines of Code (estimated) | **~120,000+** |
| Largest File | `pharmacy_provider.dart` — **17,400 lines** |
| 2nd Largest | `sales_screen.dart` — **12,181 lines** |
| `catch (e) {}` blocks found | **478+** |
| Unit Tests | **4 files** (very low coverage) |
| Architecture | Provider (ChangeNotifier) |

---

## 🔴 CRITICAL ISSUES

| # | Area | Problem | File(s) | My Recommendation |
|:--|:-----|:--------|:--------|:-------------------|
| 1 | **God Object** | `pharmacy_provider.dart` is **17,400 lines** — a single ChangeNotifier handling sales, purchases, returns, stock, customers, GST, reports, settings, and more. This is the single biggest risk in the app. | `pharmacy_provider.dart` | **SPLIT immediately** into 8-10 focused providers: `SalesProvider`, `PurchaseProvider`, `StockProvider`, `CustomerProvider`, `GstProvider`, `ReportProvider`, `SettingsProvider`, etc. Every `notifyListeners()` currently rebuilds ALL screens. |
| 2 | **Monster Screen Files** | `sales_screen.dart` = **12,181 lines**, `purchase_screen.dart` = **8,184 lines**, `server_settings_screen.dart` = **3,493 lines**, `purchase_return_screen.dart` = **3,326 lines**, `sales_return_screen.dart` = **2,925 lines**, `stock_checking_screen.dart` = **2,901 lines**, `settings_screen.dart` = **2,646 lines**, `main_shell.dart` = **2,544 lines**. | `lib/screens/` | **Extract sub-widgets** into smaller components. Each screen should be < 500 lines. Use the builder/composition pattern. |
| 3 | **Zero Test Coverage (effectively)** | Only **4 test files** exist: `widget_test.dart` (35 lines), `inventory_repository_test.dart` (27 lines), `product_ranking_calculator_test.dart` (68 lines), `tax_calculator_test.dart` (68 lines). For a 120K+ LOC billing ERP handling money, this is **dangerously low**. | `test/` | Add unit tests for: tax calculations, invoice totals, GST computation, stock adjustments, sync logic, and all financial calculations. Target **70%+ coverage** for business logic. |
| 4 | **Swallowed Exceptions** | **478+ `catch (e) {}`** blocks found across the codebase. Many just `debugPrint` the error and silently continue. Financial transactions failing silently = **data corruption risk**. | Everywhere, especially `pharmacy_provider.dart` (100+ catch blocks), `db_helper.dart` (25+) | Use structured error handling: return `Result<T>` types, show user-facing error dialogs for critical operations, and log errors to `AppLogger` with stack traces. |
| 5 | **Hardcoded Security Salt** | `SecurityCrypto` uses a hardcoded `_saltKey = "PHARMAPRO_SALT_KEY"` compiled directly into the app binary. Anyone decompiling the app can extract it. | `security_crypto.dart` | Use per-user random salts stored alongside the hash (e.g., `bcrypt` or `argon2`). At minimum, use `flutter_secure_storage` or OS keychain for the salt. |

---

## 🟠 MAJOR ISSUES

| # | Area | Problem | File(s) | My Recommendation |
|:--|:-----|:--------|:--------|:-------------------|
| 6 | **SQL Injection Risk** | `ChronicRefillService` builds SQL queries with string interpolation: `WHERE si.date >= '$date35DaysAgo'`. If any input comes from user, this is exploitable. | `chronic_refill_service.dart` | Always use parameterized queries: `WHERE si.date >= ? AND si.date <= ?` with `whereArgs`. Audit ALL `rawQuery` calls across the project. |
| 7 | **Database Helper - Giant File** | `db_helper.dart` = **2,268 lines** handling all tables, queries, migrations, and schema logic in one class. | `db_helper.dart` | Split into: `DatabaseMigrations`, `ProductQueries`, `SalesQueries`, `PurchaseQueries`, `StockQueries` using the DAO pattern. |
| 8 | **Supabase Sync Service** | `supabase_sync_service.dart` = **7,339 lines** — another god class handling ALL sync categories (products, sales, purchases, stock, returns, etc.). | `supabase_sync_service.dart` | Split into per-entity sync handlers: `ProductSyncHandler`, `SalesSyncHandler`, etc., orchestrated by a lean `SyncCoordinator`. |
| 9 | **No `mounted` Checks in Project Code** | All `mounted` check results returned were from plugin code only — **zero `mounted` checks found in your own screens**. After any `await` in a `StatefulWidget`, calling `setState` without checking `mounted` causes `setState() called after dispose()` crashes. | All screen files | Add `if (!mounted) return;` after every `await` that precedes a `setState()` call in all StatefulWidgets. |
| 10 | **Cloud Backup - Local Only** | `CloudBackupService` only creates **local file copies**. Despite its name, there is no actual cloud upload (S3, GCS, Drive). | `cloud_backup_service.dart` | Rename to `LocalBackupService` or implement actual cloud backup to Google Drive / Supabase Storage. For an ERP, offsite backups are essential. |
| 11 | **Demand Forecasting - Oversimplified** | Uses basic average × seasonal factor. No time-weighted moving average, no trend detection, no outlier removal. | `demand_forecasting_engine.dart` | Implement exponential weighted moving average (EWMA), remove outliers (e.g., bulk orders), and use actual seasonal data rather than a hardcoded 1.15 multiplier. |
| 12 | **Duplicate WhatsApp Services** | Two overlapping services: `WhatsAppService` (525 lines) and `WhatsAppNotificationService` (79 lines) do similar things. | `whatsapp_service.dart`, `whatsapp_notification_service.dart` | Merge into a single `WhatsAppService` with methods for invoice, refill, and custom messages. |

---

## 🟡 MODERATE ISSUES

| # | Area | Problem | File(s) | My Recommendation |
|:--|:-----|:--------|:--------|:-------------------|
| 13 | **Model Parsing Fragility** | `erp_models.dart` (**2,063 lines**) has dozens of `(map['key'] ?? map['altKey'] as num?)?.toDouble() ?? 0.0` chains. The `as num?` cast is applied ONLY to the fallback, not the `??` result — **operator precedence bug**. | `erp_models.dart` | Fix precedence: `((map['key'] ?? map['altKey']) as num?)?.toDouble() ?? 0.0`. Add helper: `double parseDouble(Map m, List<String> keys, {double def = 0.0})`. |
| 14 | **Print Spooler - No Error Recovery** | Queue uses a simple list; if a print task throws, it moves on. No retry, no dead-letter queue, no user notification of failure. | `print_spooler_service.dart` | Add retry logic (max 3 attempts), failed-job queue, and user notification for print failures. |
| 15 | **Clinical Interaction - Hardcoded Drug List** | Only 5 interaction rules are coded. A pharmacy app should have hundreds of interaction checks. | `clinical_interaction_service.dart` | Load interactions from a SQLite/JSON drug interaction database. Consider integrating a medical API or maintaining a versioned interaction matrix. |
| 16 | **GeoDataService - Stub** | Only 21 lines, essentially a thin wrapper. No real geo-location logic, mapping, or analytics. | `geo_data_service.dart` | Either complete with real mapping/location analytics or remove the feature to avoid confusing dead code. |
| 17 | **IsolateComputeService - Underused** | Well-designed utility for offloading heavy JSON work to isolates, but only **46 lines** and appears rarely used. Heavy JSON parsing in sync service likely runs on the main thread. | `isolate_compute_service.dart` | Wire this into `supabase_sync_service.dart` and `pharmacy_provider.dart` for all heavy JSON decode/encode operations to prevent UI jank. |
| 18 | **Ranking Cache Limit** | `RankingEngineService` caches only `.take(2000)` rankings to SharedPreferences. Pharmacies with > 2000 products lose ranking data on restart. | `ranking_engine_service.dart` | Store rankings in SQLite instead of SharedPreferences, which has size limits. |
| 19 | **No Input Validation Layer** | No centralized input validation for critical fields (GST numbers, phone numbers, batch numbers, expiry dates). Validation is scattered in UI code. | Across screens | Create a `Validators` utility class with: `isValidGSTIN()`, `isValidPhone()`, `isValidBatchNo()`, `isValidExpiry()`, etc. |
| 20 | **Export Service - Tiny Stub** | `export_service.dart` is only **68 lines**. For an ERP that generates invoices, reports, and GST filings, export capabilities seem incomplete. | `export_service.dart` | Expand with: PDF export, Excel export, CSV export, GSTR-ready JSON export as a unified service. |

---

## 🔵 MINOR / CODE QUALITY ISSUES

| # | Area | Problem | My Recommendation |
|:--|:-----|:--------|:-------------------|
| 21 | **No Dependency Injection** | All services use `static final instance = ...._internal()` singletons. Impossible to mock for testing. | Use `get_it` or `riverpod` for DI. At minimum, accept dependencies via constructor. |
| 22 | **No Logging Framework** | `debugPrint` scattered everywhere. In production, debug prints are stripped but errors are lost. | Use `AppLogger` (which already exists at 242 lines!) consistently instead of `debugPrint`. |
| 23 | **SharedPreferences for Large Data** | Rankings, settings, sync timestamps all stored in SharedPreferences. Not designed for > 1MB data. | Migrate large caches to SQLite. Keep SharedPreferences for small key-value settings only. |
| 24 | **No CI/CD** | No GitHub Actions, no automated testing, no lint checks in pipeline. | Set up GitHub Actions with `flutter test`, `flutter analyze`, and build artifacts. |
| 25 | **Magic Numbers** | Hardcoded values like `seasonalFactor = 1.15`, `15 days safety stock`, `45 days max stock`, threshold `2.0` for tax mismatch. | Extract to named constants or make configurable in settings. |
| 26 | **Inconsistent Naming** | Mix of `snake_case` DB columns (`sale_rate`) and `camelCase` Dart fields (`saleRate`) with manual mapping everywhere. | Use a consistent mapping layer or code generation (`json_serializable` / `freezed`). |
| 27 | **No Offline-First Error UI** | When sync fails or server is unreachable, errors only go to `debugPrint`. Users have no visual indicator of sync health. | Add a persistent sync status bar (already partially in `main_shell.dart` — complete it). |
| 28 | **GSTR-2B Reconciliation** | Only basic invoice-level matching. No line-item reconciliation, no ITC claim tracking, no mismatch resolution workflow. | Expand to support line-item matching and provide a reconciliation dashboard UI. |
| 29 | **Invoice Recovery Service** | Present at 473 lines, but unclear if auto-recovery is actually triggered on crash. | Verify crash-recovery flow end-to-end. Add automated tests for mid-transaction crash scenarios. |
| 30 | **PDF Worker Service** | Only 70 lines — likely just a wrapper. For an ERP generating hundreds of invoices daily, PDF generation should be optimized with templates and caching. | Pre-compile PDF templates, use isolates for batch generation, cache common elements (headers, footers). |

---

## 📁 Files That Need Urgent Refactoring (by size)

| File | Lines | Urgency |
|:-----|------:|:--------|
| `pharmacy_provider.dart` | 17,400 | 🔴 Critical |
| `sales_screen.dart` | 12,181 | 🔴 Critical |
| `purchase_screen.dart` | 8,184 | 🔴 Critical |
| `supabase_sync_service.dart` | 7,339 | 🟠 High |
| `server_settings_screen.dart` | 3,493 | 🟠 High |
| `purchase_return_screen.dart` | 3,326 | 🟡 Medium |
| `sales_return_screen.dart` | 2,925 | 🟡 Medium |
| `stock_checking_screen.dart` | 2,901 | 🟡 Medium |
| `settings_screen.dart` | 2,646 | 🟡 Medium |
| `main_shell.dart` | 2,544 | 🟡 Medium |
| `db_helper.dart` | 2,268 | 🟡 Medium |
| `sales_report_screen.dart` | 2,195 | 🟡 Medium |
| `erp_models.dart` | 2,063 | 🟡 Medium |

---

## ✅ What's Done Well

| Area | Comment |
|:-----|:--------|
| **Transaction Safety** | `executeSerializedTransaction` with `Lock` and atomic DB writes is excellent. |
| **Watchdog System** | `AppWatchdog` and `WatchdogMixin` for timeout detection is professional-grade. |
| **Invoice Recovery** | Having an `InvoiceRecoveryService` shows forethought about data integrity. |
| **Clinical Interactions** | Even basic drug interaction checking puts this above most pharmacy software. |
| **Delta Sync** | Having both full sync and delta sync shows good offline-first architecture. |
| **Unsaved Change Handler** | `UnsavedHandler` protecting against accidental data loss is a great UX pattern. |
| **Tax Calculator** | Dedicated GST/tax calculation with proper CGST/SGST/IGST splitting. |
| **Schedule H/H1 Compliance** | Drug scheduling compliance dialog shows regulatory awareness. |
| **PDF/Thermal/Dot Matrix Printing** | Supporting 3 printer types covers real pharmacy needs. |
| **Search Debouncer** | Proper debouncing for search performance. |

---

## 🎯 Recommended Priority Order

### Phase 1: Safety & Stability (Do First)
1. Fix operator precedence bug in `erp_models.dart` (Issue #13)
2. Add `mounted` checks in all screens (Issue #9)
3. Fix SQL injection in `chronic_refill_service.dart` (Issue #6)
4. Add unit tests for financial calculations (Issue #3)

### Phase 2: Architecture (Next Sprint)
5. Split `pharmacy_provider.dart` into focused providers (Issue #1)
6. Split `sales_screen.dart` into sub-widgets (Issue #2)
7. Split `supabase_sync_service.dart` (Issue #8)
8. Implement proper error handling with Result types (Issue #4)

### Phase 3: Quality (Ongoing)
9. Add CI/CD pipeline (Issue #24)
10. Centralized input validation (Issue #19)
11. Replace SharedPreferences with SQLite for large data (Issue #23)
12. Complete cloud backup implementation (Issue #10)

### Phase 4: Polish (Future)
13. Code generation for models with freezed (Issue #26)
14. Expand clinical interaction database (Issue #15)
15. Improve demand forecasting algorithm (Issue #11)
16. Add dependency injection (Issue #21)
