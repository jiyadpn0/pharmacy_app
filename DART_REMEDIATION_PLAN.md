# Dart Analyzer Remediation Plan

## Current baseline

Current baseline after the first remediation passes: `flutter analyze --no-pub` reports **157 analyzer findings and no compile errors**, down from the initial 206 findings. The latest run includes provider/model fixes already present in the accepted source, lifecycle-safe handling of async UI work, removal of the direct protected `notifyListeners` call, deprecated API cleanup, and several unused/type-redundancy cleanups. Treat this run as the new baseline.

## Execution plan

### Phase 1 — Correctness and lifecycle safety — complete for current analyzer findings
- Current analyzer reports no compile errors; the previously reported provider/model/sync API mismatches are resolved in the current source.
- Added lifecycle checks or captured dependencies around async UI work in startup, sales save, server settings, and discrepancy reconciliation.
- Removed the direct protected `notifyListeners` call from invoice recovery; the provider's own reload path already notifies listeners.
- Recheck the remaining async-context warning, if any, in the complete analyzer output during the next pass.

### Phase 2 — SDK and package migration — substantially complete
- Migrated the flagged purchase switch color to `activeThumbColor` and added a clear deprecation message to the WhatsApp wrapper.
- Current source already uses `withValues`, `onReorderItem`/no deprecated reorder callback, and Supabase `publishableKey` where applicable.
- Recheck the remaining deprecated API findings, if any, in subsequent complete analyzer output.

### Phase 3 — Remove dead code and simplify types — in progress
- Simplified redundant null-aware access and type checks in `pharmacy_provider.dart`.
- Marked immutable sales-provider fields `final` and removed the unused `isLatest` local from product registration.
- Continue reviewing unused state and helpers for side effects before removal.
- Review unused imports, locals, fields, and private helpers. Remove only declarations confirmed to have no side effects or dynamic/reflection use.
- Simplify redundant null-aware access, null checks, casts, and unreachable switch defaults.
- Keep domain-critical transaction, sync, and pharmacy behavior unchanged.

### Phase 4 — Consistency and maintainability — queued
- The current remaining 157 findings are mostly style and cleanup findings such as missing braces, const opportunities, and unused declarations.
- Add braces around single-statement control-flow branches.
- Apply safe `const` improvements and remove confirmed unused imports/helpers.
- Avoid broad unreviewed edits in the purchase, sales, sync, and inventory flows.
- Add braces around single-statement control-flow branches.
- Apply safe `const` and `final` improvements.
- Remove unnecessary imports and interpolation braces.

## Review and verification
- Latest `flutter analyze --no-pub`: **157 issues found**, no compile errors. The output is truncated, so remaining per-line findings still need to be worked through in Phases 3 and 4.
- Work in small, reviewable file groups; do not apply broad formatter or code-fix changes to business-critical code without inspecting the diff.
- Re-run `flutter analyze --no-pub` after each phase and update the review with the remaining count and any newly surfaced issues.
- No tests were added or run. Do not treat a lower warning count as sufficient if behavior or data flow changes are introduced; inspect those changes explicitly.
