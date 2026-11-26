# Multi-Terminal Synchronization & Collision-Proof Architecture Plan
**Target Version:** v4.3.0  
**Domain:** Pharmacy Multi-Counter POS & Cloud ERP  
**Scope:** Permanent elimination of sequence collisions, missed entries, UI freezing, and banner friction across multiple counters.

---

## 1. Problem Root-Cause Summary
1. **Sequence Number Collisions:**
   - Both terminals independently pull sequence `1` (or next integer) from their local databases.
   - When Counter 1 and Counter 2 save simultaneously, both write Entry `#1` or Bill `#105`.
   - The cloud database / sync engine either overwrites the earlier bill or drops the latter due to primary key / unique constraint conflicts.
2. **Dropped Incoming Sync Events:**
   - Realtime/LAN notifications fire at the exact same millisecond during simultaneous saves.
   - If a background sync cycle is already running, the engine logs:
     `DeltaSyncService: Catch-up sync skipped because a sync cycle is already running.`
     The simultaneous entry is dropped from immediate view until an hourly manual pull.
3. **Friction-Heavy UI Reloads (The Purple Banner):**
   - The UI shows a blocking banner: `Live Notice: Purchase Entry #1 was updated on another PC. [RELOAD PURCHASE]`.
   - Rather than silently updating the bottom table (`Recent Purchases`), it demands manual user intervention.

---

## 2. Step-by-Step Implementation Plan

### Step 1: Terminal Prefix & Independent Counter Sequences (Zero Collision Guarantee)
* **Goal:** Guarantee that Counter 1 and Counter 2 can save 1,000 bills at the exact same millisecond with zero collisions.
* **Actions:**
  1. In `ServerConfigService`: Expose a clean, persistent `terminalPrefix` (e.g., `P1-` on PC 1, `P2-` on PC 2, configured automatically from `terminalId`).
  2. In `PharmacyProvider`:
     - Update sequence calculation for sales invoices and purchase entries:
       - Counter 1 produces: `P1-1`, `P1-2`, `P1-3`...
       - Counter 2 produces: `P2-1`, `P2-2`, `P2-3`...
     - Daily/Monthly total sales reports automatically aggregate all terminal prefixes (`P1-*`, `P2-*`, un-prefixed legacy) seamlessly.
  3. Allow optional toggle in Server Settings for single-counter pharmacies wanting plain numeric sequences.

---

### Step 2: Transactional FIFO Inbound Sync Queue (Zero Missed Entries)
* **Goal:** Guarantee that every incoming bill or purchase from another PC is processed and persisted, even under heavy simultaneous load.
* **Actions:**
  1. Create `SyncInboundQueueService`:
     - Dedicated thread-safe FIFO queue for incoming LAN UDP/TCP packets and Supabase Realtime payloads.
     - When an event arrives, it is immediately enqueued without waiting for active sync locks.
  2. Sequential Worker Drain:
     - Worker drains the queue item-by-item in SQLite transactions.
     - Never drops or skips an event even if a full sync cycle is already active.
  3. Outbox-to-Inbound Acknowledgment:
     - LAN broadcast includes `event_id`. Receiver terminal acknowledges receipt; if unacknowledged within 300ms, fallback to Supabase cloud sync takes over.

---

### Step 3: Non-Destructive Silent UI Merging (No Annoying Banners)
* **Goal:** Both PCs instantly reflect each other's live entries without interrupting active typing.
* **Actions:**
  1. In `PurchaseScreen` and `BillingScreen`:
     - **If the user is editing an entry:**
       - Silently append the incoming entry from the other counter directly into `_recentPurchasesList` / `_recentSalesList`.
       - Update the bottom totals and vendor ledgers instantly.
       - Remove the blocking purple banner unless the operator is literally modifying the *exact same terminal-prefixed document*.
     - **If the user is on a blank new entry:**
       - Do not interrupt; keep their active input row focused.
  2. Live Stock Reflection:
     - When Counter 1 sells items, update the batch stock in memory so Counter 2's stock indicator immediately shows the reduced quantity without re-parsing the 52k product master.

---

### Step 4: LAN First, Cloud Second Fallback Pipeline
* **Goal:** 1ms to 5ms local network response time between counters in the shop, independent of internet speed.
* **Actions:**
  1. Verify and bind high-speed TCP socket pipe between Counter 1 and Counter 2 on port 9998.
  2. Direct LAN transmission of completed invoice JSON immediately upon pressing `Save`.
  3. Cloud Supabase sync operates asynchronously in the background for remote off-site backups and owner mobile pulse monitoring.

---

### Step 5: Verification & Quality Assurance
* **Test Case A: Simultaneous Billing Test:**
  - Open Sales/Purchase on PC 1 and PC 2 simultaneously.
  - Save bills at the exact same second on both PCs.
  - Verify both bills exist in SQLite, Supabase, and the Recent Bills list on both screens.
* **Test Case B: Offline Counter Test:**
  - Disconnect internet on PC 2.
  - Save bills on PC 2 and PC 1.
  - Reconnect internet; verify all queued transactions sync cleanly without overwriting.
* **Test Case C: Full Code Analysis:**
  - Run `flutter analyze` ensuring 0 errors, 0 warnings.
  - Build release and bump version.
