# Waiter Module — QA Findings & Bug Report

**Scope:** `lib/waiter_module/**` plus its integration seams (`lib/locator.dart`,
`lib/screens/login_screen.dart`, `lib/screens/branch_selection_screen.dart`,
`lib/screens/table_management_screen.dart`, `lib/services/cashier_mesh_bootstrap.dart`,
`lib/services/waitlist_mesh_bridge.dart`, `lib/services/display_app_service_parts/*`).
**Oracle:** `docs/SRS_Waiter_Module.md` (FR‑IDs referenced inline).
**Status:** analysis only — no code was changed, no tests authored. Printing/receipt
code is reported on but never modified. Line numbers were verified against the source
on `main` at audit time; treat them as anchors, re‑check before editing.

Severity scale: **Critical** (data loss / money / unrecoverable stuck state),
**High** (functional break, recovery needs manual cashier action), **Medium**
(narrow race or spec deviation with a workaround), **Low** (cosmetic / theoretical /
dead code).

---

## Part A — Root cause: "table stuck at *جاري اخذ الطلب*" (the reported symptom)

> *"After a waiter opens a table and then leaves the order screen without sending
> anything, the table still shows 'someone is taking an order' — on the waiter's own
> grid and/or on the cashier's table‑management screen."*

The flag is set the moment the order screen mounts and is supposed to be cleared by a
`released` broadcast from `WaiterOrderScreen.dispose()`. The symptom is **every way that
`released` fails to be (a) emitted, (b) delivered to a peer, or (c) honoured on
restart.** Each distinct path below is independently sufficient to wedge the table.

### A‑1. Order screen opens ⇒ `takingOrder` broadcast + persisted to disk

`WaiterOrderScreen.initState()` → `_announceAssignment()`
(`waiter_order_screen.dart:402‑433`) broadcasts a `TableLifecycleEvent`
(`takingOrder` when the local cart is empty, `assigned` when it already has items).
`broadcastTableEvent` (`waiter_controller.dart:714‑729`) applies it to the local
registry **then** fans it out. `WaiterTableRegistry.apply()`
(`waiter_table_registry.dart:78‑99, 196‑201`) writes `takingOrder=true` and
**schedules a 300 ms‑debounced disk flush**. The cashier records it
(`table_management_screen.dart:144‑150` → `_takingOrderTables.add(tableId)`); other
waiters' grids show it too. So *merely opening the order screen* paints the table as
"taking order" on every peer and (after 300 ms) on this device's disk.

### A‑2. The only un‑set path — `WaiterOrderScreen.dispose()` — is gated by **four** conditions

`waiter_order_screen.dart:296‑334`. `released` is broadcast only if **all** of:
`me != null` *and* `iAmOwner` (`ownerId == null || ownerId == me.id`) *and*
`cartEmpty` *and* `notCommitted` (`!paymentPendingFor && !paidFor`) *and*
`wasJustTakingOrder` (`takingOrderFor || cartEmpty`). Distinct stuck paths:

1. **App force‑killed while the order screen is still on screen** (before `dispose()`).
   `takingOrder` was broadcast (A‑1) and, if >300 ms elapsed, persisted to disk
   (`waiter_table_registry.dart:277‑281, 297‑318`). No `released` ever goes out.
   On next launch `WaiterTableRegistry.hydrate` (`waiter_table_registry.dart:216‑272`)
   reloads `takingOrder=true`; `WaiterTablesScreen._load()`
   (`waiter_tables_screen.dart:379‑417`) calls
   `reconcileWithBackend(availableIds, selfId: self.id)` — and that method
   **deliberately keeps a self‑owned `takingOrder` row even when the backend reports the
   table available** (`waiter_table_registry.dart:373‑378`). ⇒ the waiter's own grid
   shows "جاري اخذ الطلب" forever; the cashier (if it didn't restart) shows it forever.
   *Fix sketch:* don't persist `takingOrder` (it's transient local state); or stamp it
   with a timestamp and expire on hydrate; or only honour the self‑owned guard while
   `controller.activeOrderingTableId == tableId` (i.e. the screen is *currently* open).

2. **`dispose()` runs and broadcasts `released`, but the WS sink swallows it.**
   `broadcastTableEvent(released)` applies locally (waiter grid clears) then
   `_net?.broadcast(...)` → `WaiterNetworkService.broadcast`
   (`waiter_network_service.dart:353‑360`) does `conn.channel.sink.add(encoded)` inside
   `try { … } catch (_) {}`; a half‑dead socket (Wi‑Fi flap at that instant) buffers
   the bytes and loses them on drop. There is **no replay for `released`** —
   `_pushOwnedTablesSnapshotTo` on HELLO (`waiter_controller.dart:1492‑1524`) only
   re‑pushes tables the device *still owns*, and after `apply(released)` the row is gone.
   ⇒ the cashier (and any peer) keeps `takingOrder` indefinitely.
   *Fix sketch:* see A‑5 (cashier‑side reconcile / age‑out).

3. **Process force‑killed *during* `dispose()`** — after `apply(released)` (memory only)
   but before the `unawaited(_flushPersist())` it triggered
   (`waiter_table_registry.dart:189‑195`) finishes its `setString` pair. On restart the
   disk still has `takingOrder=true` ⇒ same outcome as path 1, plus the cashier (path 2).

4. **Waiter ends shift while still "owning" a `takingOrder` table** (e.g. the `released`
   from a prior pop‑back was dropped — path 2). `stop()` sends `WAITER_LEAVE`
   (`waiter_controller.dart:1552‑1561`); the cashier's handler only does
   `roster.markOffline` (`waiter_controller.dart:1190‑1192`) — it does **not** release the
   leaving waiter's tables. ⇒ a `takingOrder` row owned by the departed waiter survives on
   the cashier. (Beware: a blanket "release this waiter's tables on LEAVE" must *not*
   evict `paymentPending` rows — the booking still exists on the backend.)

5. **The cashier never reconciles its registry against the backend.**
   `lib/screens/table_management_screen.dart` calls `getTables()` in `_loadTables`
   (`:541`) but never calls `tableRegistry.reconcileWithBackend(...)`, unlike
   `waiter_tables_screen.dart:395`. And `_takingOrderTables` is rebuilt on **every**
   nav‑back from `tableRegistry.takingOrderFor` in `_hydrateFromRegistry`
   (`table_management_screen.dart:572‑593`), and is **never aged out**. ⇒ once paths
   1‑4 leave a stale row in the cashier's registry, every nav‑away/back re‑lights the
   "جاري اخذ الطلب" pill until a `released`/`assigned`/`updated`/`paymentPending`/`paid`
   event arrives for that exact table id — which, in paths 1‑4, never does.
   *Fix sketch:* in `_loadTables`, call `tableRegistry.reconcileWithBackend(...)` and
   re‑derive `_takingOrderTables`; and/or TTL `_takingOrderTables`.

6. **`reconcileWithBackend` ignores `assigned`/`updated` rows** — the *sibling* stuck
   bug. If the waiter opens a table, adds one item (→ `_broadcastUpdate()` →
   `kind: updated`, which `apply()` records with `takingOrder=false, itemCount>0`,
   `waiter_table_registry.dart:118‑138`), then walks away with the back button without
   removing the item: `dispose()`'s `cartEmpty == false` ⇒ no `released`. The table is
   left at `kind=updated` on every peer with no backend booking. `reconcileWithBackend`
   only evicts `paid || paymentPending || takingOrder` (`waiter_table_registry.dart:379`)
   — so an `updated` (draft‑only) row with no backend booking is **never** cleared. The
   table shows "occupied by X · N items" forever on both the waiter grid and the cashier.
   Same applies to a stale `assigned` row (e.g. a pickup‑claim the waiter abandoned).
   *Fix sketch:* extend `reconcileWithBackend` to evict `assigned`/`updated` rows when the
   backend reports the table available **and** the row has no `orderId`; or have
   `dispose()` release the table when the cart holds only drafts (no sent items, no
   booking id).

7. **The self‑owned‑`takingOrder` guard has no "is the order screen actually open?"
   check.** `reconcileWithBackend(availableTableIds, selfId)`
   (`waiter_table_registry.dart:364‑391`) keeps the row purely on
   `row.takingOrder && row.waiterId == selfId`. It never consults
   `WaiterController.activeOrderingTableId`. So the guard that's meant to protect a
   *currently composing* waiter is exactly what makes the state permanent once the screen
   has closed and the `released` was missed. *Fix sketch:* pass
   `controller.activeOrderingTableId` in and only keep the row if it matches `tableId`.

8. **`iAmOwner` flips to `false` between init and dispose ⇒ no `released`.** If the
   registry owner for the table changes between `_announceAssignment` and `dispose()`
   (today only reachable via a pickup‑claim race — and in that case the new owner's
   `assigned` already cleared `takingOrder` on peers, so it's currently benign), the
   `iAmOwner` clause silently skips the release. It's a latent gap: any future path that
   reassigns the owner without clearing `takingOrder` will strand it.
   *Fix sketch:* track an `_announcedTakingOrder` bool in the State and, in `dispose()`,
   broadcast `released` whenever this device announced `takingOrder` for this table and
   never sent items — independent of who the registry thinks owns it now.

9. **Refresh gap on the waiter's own grid.** `_onLifecycle` defers its `setState` to a
   post‑frame callback (`waiter_tables_screen.dart:135‑171`); if the screen is mid‑rebuild
   the `if (!mounted) return;` can drop the `_tables[idx].status = available` flip. The
   registry row was already removed, but the card's overlay path renders
   `ownerId == null ? t.status : occupied` and `t.status` is the stale `occupied` that the
   build method itself wrote via the `..status = …` cascade on `_tables[i]` (see B‑13).
   Cosmetic, but it can make a *released* table keep showing as occupied until the next
   `getTables()` poll. *Fix sketch:* never mutate `_tables` elements; derive status from
   the registry on every build.

**Summary of the fix surface (none implemented):** (i) stop persisting `takingOrder` /
expire it on hydrate; (ii) make the `reconcileWithBackend` self‑owned guard conditional
on the order screen being open *right now*; (iii) call `reconcileWithBackend` on the
cashier side and age out `_takingOrderTables`; (iv) have `dispose()` release the table
based on "this device announced it and never sent items" rather than the four‑clause
check; (v) extend `reconcileWithBackend` to cover `assigned`/`updated` rows with no
`orderId`.

---

## Part B — Bug & risk findings (by area)

### B‑1 · Closing a table can charge the customer with no receipt and leave the table stuck — `processBill` has no mounted/session guard · **Critical** · `waiter_billing_service.dart:580‑917`, `waiter_order_screen.dart:1162‑1335`, `table_details_dialog.dart:312‑417`

`_runBillFlow` / `_printBill` run with the order screen **fully interactive** ("Fire‑and‑forward: no blocking progress dialog", `waiter_order_screen.dart:1179‑1182`). For a **cash** payment the entire flow is `await _billing.processBill(...)` then `if (!mounted) return;`. If the waiter taps the AppBar back button (or the app navigates away) during `processBill` — `createBooking` + `createInvoice` are ~1‑2 s — the screen is disposed, but `processBill` keeps running to completion: the booking and invoice are created on the backend, the customer is "paid". Then `_runBillFlow` hits `if (!mounted) return;` and **never** broadcasts `paid`, never prints the receipt, never shows the success sheet, never clears the cart's pending‑booking id. The waiter's grid and the cashier still show the table at `paymentPending` (the optimistic broadcast at `waiter_order_screen.dart:1074‑1084`). The cashier then "Create Invoice"s again from the details dialog ⇒ duplicate invoice / double‑charge; or re‑collects cash. For a **card** payment the window is smaller (between `createBooking` returning and the NearPay UI appearing) but the same outcome.
*Repro:* tables → open a `paymentPending` table → Create Invoice → pick **cash** → tender dialog pops → during the ~1 s `processBill`, tap the AppBar back arrow → on the backend the invoice exists & is paid; on every device the table still says "بانتظار الدفع"; no receipt printed.
*Root cause:* `processBill` is fire‑and‑forget from a button tap, and the post‑success side effects (broadcast, print, cart cleanup) live *after* a `mounted` check that fails once the route is popped; `processBill` itself has no `mounted`/session‑generation awareness.
*Fix sketch:* either block the order screen behind a non‑dismissible barrier for the duration of `processBill`; or move the `paid` broadcast + cart cleanup *inside* `WaiterBillingService` (or a controller method) keyed off `bookingId` so they don't depend on the screen being alive; or, on `dispose()` while a bill is in flight, queue a "reconcile this bookingId on next start" marker.

### B‑2 · Config messages are honoured from a non‑viewer sender — FR‑NET‑8 violation · **High (security)** · `waiter_controller.dart:1259‑1276`, `waiter_config_store.dart`

`FR‑NET‑8` / `NFR‑SEC‑4`: *"Config messages (`CONFIG_KITCHEN_PRINTERS`, `CONFIG_KDS_ENDPOINT`, …): only honoured **from** / by viewer sessions."* The **send** side is guarded (`broadcastKitchenPrintersConfig`/`broadcastKdsEndpoint`/`pushKdsEndpointTo` all `if (!self.isViewer) return;`). But the **receive** side only checks *our* role, not the *sender's*: `case configKdsEndpoint: if (self.isViewer) break; … configStore.applyKdsEndpoint(msg.data, sourceId: msg.senderId);` — a waiter receiving a `CONFIG_KDS_ENDPOINT` from **another waiter** (or any LAN device that can produce a signed envelope) applies it. ⇒ a buggy/compromised waiter device — or a LAN attacker with the compile‑time pepper (`MeshAuthService._pepper`) — can repoint every waiter's KDS at an attacker‑controlled host and redirect/observe kitchen orders, or push a bogus printer list.
*Repro:* on device B craft a signed `CONFIG_KDS_ENDPOINT` envelope with `sender_id` not starting with `viewer-` (or with *any* `sender_id` — see B‑3) and `data.host` = attacker IP → waiter A's `DisplayAppService` reconnects there (`waiter_config_store.dart:363‑385`).
*Root cause:* the anti‑spoof switch arms covered `WAITER_CALL_ACCEPTED`, `TABLE_PICKUP_*` (sender‑prefix / `sender_id` match) but not the config messages.
*Fix sketch:* in `_handleIncoming`, for `configKitchenPrinters`/`configKdsEndpoint`/`configSyncRequest` also require `msg.senderId.startsWith(Waiter.viewerIdPrefix)` before applying/responding.

### B‑3 · `viewer-` prefix is a typo‑guard, not an auth boundary — anyone with the pepper can impersonate the cashier · **Medium (security, by design but worth stating)** · `waiter_controller.dart:1293, 1328, 1373`, `mesh_auth_service.dart:36‑37`

The pickup/cancel anti‑spoof checks (`!msg.senderId.startsWith(Waiter.viewerIdPrefix)` ⇒ drop) only verify the *string shape* of `sender_id`. A device that holds the mesh key (the pepper is compiled into the APK — `NFR‑SEC‑2` acknowledges this) can set `sender_id` to `"viewer-anything"` and pass every viewer‑gated check (issue pickups, cancel pickups, and — combined with B‑2 if fixed — push config). Likewise `WAITER_CALL_ACCEPTED` / `TABLE_PICKUP_CLAIMED` only require `data.waiter_id == sender_id`, both attacker‑chosen. This matches the documented threat model (defends against "random LAN guest", not "attacker with the APK") — flagged so it isn't mistaken for a real boundary, and so the config‑message gap (B‑2) is fixed *at least to the same level* as the rest.

### B‑4 · Mesh key can be derived against a stale `sellerId` (`0`) and never re‑derived ⇒ silent split‑brain with the cashier · **Medium** · `waiter_controller.dart:388‑395`, `mesh_auth_service.dart:46‑54`

`WaiterController.start()` calls `MeshAuthService.deriveKey(branchId, ApiConstants.sellerId.toString())` exactly once. If `ApiConstants.sellerId` is still `0` (the SRS §2.6 / the inline comment both call out this "rare boot race"), the waiter's key is scoped `branchId:0` while the cashier's is `branchId:<realSellerId>`. The keys differ ⇒ every message between them is HMAC‑rejected silently (`waiter_network_service.dart:211‑214`) ⇒ the waiter looks "alone on the LAN" with no error, until the app is fully restarted. `deriveKey` is never re‑called after `sellerId` is populated.
*Repro:* hard to force reliably; force a slow profile/login so `start()` runs before `AuthService` writes `sellerId`.
*Root cause:* one‑shot key derivation with no re‑derive when `sellerId` later changes; comment even says "fall back to an empty seller scope" but the code emits `"0"`.
*Fix sketch:* re‑derive the key (and re‑announce) whenever `ApiConstants.sellerId` transitions from `0` to a real value, or block `start()` until `sellerId != 0`, or surface a warning if it's `0`.

### B‑5 · `WaiterTableRegistry.clearAll()` / `clearPersisted()` race the persist tail ⇒ wiped state can resurrect on next sign‑in · **Medium (privacy / FR‑SES‑10 / NFR‑REL‑4)** · `waiter_table_registry.dart:290‑336, 412‑420`, `waiter_cart_store.dart:404‑443, 454‑467`

The registry serializes `_flushPersistOnce` calls with a `_persistTail` future chain — but `clearPersisted()` (called from `clearAll()` on logout/branch‑switch) is **not** chained onto `_persistTail`. So if a `_flushPersistOnce` is mid‑flight (`setString(backup,E)` … `setString(primary,E)`) when `clearPersisted` runs (`remove(primary)` … `remove(backup)`), the writes interleave and the disk ends up holding `primary = E` again. ⇒ the just‑cleared registry rows survive; on the next sign‑in (same waiter, same `branch+name` scope) `hydrate` reads them back — a device‑hand‑off privacy leak. `WaiterCartStore` is **worse**: it has no `_persistTail` chain at all (`waiter_cart_store.dart:398‑443`), so two overlapping debounced `_flushPersist` runs can already leave the two slots holding *different* snapshots, breaking the "backup is the pre‑commit snapshot" invariant `hydrate` relies on; `clearPersisted` racing one of them resurrects the cart.
*Repro:* timing‑dependent; more likely on a busy/slow Sunmi filesystem during a flurry of `apply()`/`addItem()` calls immediately before "end shift".
*Fix sketch:* route `clearPersisted()` through `_persistTail` (registry) and add a `_persistTail` chain to `WaiterCartStore` mirroring the registry, with `clearPersisted` chained onto it.

### B‑6 · `apply(updated)` keeps `paymentPending`/`paid` from the previous row · **Low/Medium** · `waiter_table_registry.dart:118‑138`

`updated` is the only `apply` branch that does `(prev ?? _empty(event)).copyWith(...)` without resetting `paymentPending`/`paid`. `_pushOwnedTablesSnapshotTo` sends `updated` for non‑pay‑later, non‑paid owned tables (`waiter_controller.dart:1498‑1512`); if a peer's registry already had that table stale‑marked `paymentPending`, the incoming `updated` snapshot won't clear it ⇒ the peer keeps showing "بانتظار الدفع" / an Edit‑Order button for a table that's actually just an open draft.
*Fix sketch:* in the `updated` branch set `paymentPending: false, paid: false` (matching the `assigned`/`takingOrder` branches) — or be deliberate about which transitions are allowed to demote those flags.

### B‑7 · Pickup claim winner is decided by **device clock** timestamps, contradicting FR‑PU‑3 · **Medium** · `waiter_pickup_store.dart:72‑105`, `waiter_controller.dart:903‑948`

`FR‑PU‑3`: *"the first waiter to claim wins … the UI never reverts to an older claimer."* `WaiterController.claimTablePickup` short‑circuits on a *locally* already‑claimed request, but `WaiterPickupStore.markClaimed` resolves conflicts by **earlier `claimedAt` wins** (timestamps from different tablets). With clock skew, a waiter who tapped *second* but has a slow clock produces an earlier `claimedAt`, so on receiving that claim the first claimer's device **overrides** "claimed by A" → "claimed by B" — the UI reverts. Worse, the *registry* converges differently: both `claimTablePickup` calls broadcast `TABLE_ASSIGN` with themselves as owner, and `apply(assigned)` is last‑write‑wins by **arrival order**, so a peer can end up with `registry owner = A` but `pickup feed = "claimed by B"`. Two waiters may walk to the same table.
*Repro:* skew two tablets' clocks by ~1 s; have both tap Accept on the same pickup within that second.
*Fix sketch:* decide the winner by **first claim received on the wire** (or a per‑request monotonic Lamport counter the cashier seeds), not by cross‑device wall‑clock; make the `assigned` fold use the same winner.

### B‑8 · Near‑simultaneous double‑accept of a broadcast call leaves devices disagreeing on "accepted by X" · **Medium** · `waiter_message_store.dart:59‑75`, `waiter_controller.dart:691‑712`

`markAccepted` is "first acceptance wins" (`if (existing.isAccepted) return;`) with **no tie‑break**. If waiters A and B both tap Accept before either's `WAITER_CALL_ACCEPTED` arrives at the other: A's device keeps "accepted by A" (rejects B's), B's keeps "accepted by B", and third‑party waiters latch onto whichever arrived first. The feed never converges. (`FR‑MSG‑3` implies convergence.) Also `acceptCall` has no `isViewer` guard (`waiter_controller.dart:691‑694`) — not reachable from the cashier UI (the Accept button is hidden for viewers) but an inconsistent role guard vs. every other outbound action.
*Fix sketch:* tie‑break `markAccepted` deterministically (e.g. earliest `acceptedAt`, then `waiterId`), the same way the pickup store does (after B‑7 is fixed, reuse that scheme); add `if (self.isViewer) return;` to `acceptCall`.

### B‑9 · Incoming‑call **sound** is not suppressed while the waiter is composing an order · **Low/Medium (spec)** · `waiter_controller.dart:1194‑1207`, FR‑CTL‑7 / NFR‑USE‑3

`FR‑CTL‑7` / `NFR‑USE‑3`: *"While [`activeOrderingTableId`] is set, disruptive UI (pickup banner **sound**, incoming‑call **sound**) shall be suppressed."* The pickup path honours this (`if (!isTakingOrderNow) notifications.playCall();`, `waiter_controller.dart:1308‑1311`) but the `waiterCall` path plays unconditionally: `if (incoming.isCall) { notifications.playCall(); _callStream.add(incoming); }`. The *banner* is suppressed (`WaiterHomeScreen._onPickupRequest`/`_onIncomingCall` — actually `_onIncomingCall` is **not** suppressed either, `waiter_home_screen.dart:80‑83`), but the sound definitely isn't.
*Fix sketch:* gate `notifications.playCall()` (and the banner) on `!isTakingOrderNow` in the `waiterCall` case too, mirroring the pickup path.

### B‑10 · `WaiterKitchenBridge.sendNewOrder` has no KDS‑ACK / retry — the cashier path does · **Medium** · `waiter_kitchen_bridge.dart:29‑54`, vs. `lib/screens/main_screen_parts/main_screen.payment.dart:798‑849`

The cashier dispatches kitchen orders via `_dispatchOrderToKdsWithAck` → `_waitForKdsAck` (waits ~900 ms for the KDS to ACK `orderId`, falls back to a mode switch + resend). The waiter just calls `_display.sendOrderToKitchen(...)` once and returns. `WaiterOrderScreen._dispatchToKds` decides "online vs. enqueue" purely on `_bridge.isConnected` (= `DisplayAppService.isConnected`, i.e. WS up) — "WS up" ≠ "order delivered/processed". A frozen‑but‑connected KDS ⇒ the order is silently lost and **not** queued in the outbox (`FR‑ORD‑6` is satisfied only for a *down* socket).
*Fix sketch:* have `WaiterKitchenBridge.sendNewOrder` await/check `DisplayAppService.lastOrderAckId == orderId` (the plumbing already exists for the cashier) and, on no‑ACK, fall through to `WaiterOrderOutbox.enqueue`.

### B‑11 · Quantity is rounded in `buildBookingPayload` but **not** in `buildBookingPayloadFromSnapshot` ⇒ waiter‑close vs. cashier‑close produce different bookings for fractional items · **Medium** · `waiter_billing_service.dart:443‑463 vs. 477‑490`, `updateBookingItems` `:544`

`buildBookingPayload` (waiter's own Pay‑Later / Edit) does `'quantity': it.quantity.round().clamp(1, 9999)` — a 0.5 kg line becomes `1`. `buildBookingPayloadFromSnapshot` (cashier creating the invoice on the waiter's behalf, `table_details_dialog.dart`) does `'quantity': it.quantity` (fractional, untouched). `updateBookingItems` also rounds. So the same cart, closed by the waiter vs. the cashier, posts different quantities/totals to the backend; and the KDS ticket (`_cartItemToWire` sends the fractional qty, `waiter_order_screen.dart:775‑789`) won't match the booking. The `createInvoice` 422‑retry that re‑derives the total from the backend's error message (`waiter_billing_service.dart:805‑827`) papers over the total mismatch but not the quantity mismatch on the booking itself. *Note:* if the cashier's own invoice‑items builder also rounds, then the waiter‑direct path is consistent with it and only the *snapshot* path is the outlier — verify against the cashier and pick one rule.
*Fix sketch:* use a single quantity normalisation across all three builders; if fractional quantities are legitimate (the repo has a "DECIMAL LIKE KILO OR HALF" capture), don't round at all.

### B‑12 · Force‑kill within 300 ms of a successful Pay‑Later ⇒ duplicate kitchen ticket on re‑entry · **Medium** · `waiter_cart_store.dart:105‑112, 398‑402`, `waiter_order_screen.dart:594‑773, 131‑153`

On a successful `_payLater`, `_cart.markDraftAsSent(tableId)` only **schedules** the 300 ms‑debounced disk flush (`waiter_cart_store.dart:111`), whereas the registry's `paymentPending` write flushes **immediately** (`waiter_table_registry.dart:191‑195`). Force‑kill in that 300 ms window ⇒ on restart the registry has `paymentPending` + `orderId`, but the cart still holds the items as **drafts** (not sent). `_rehydrateSentFromBackendIfNeeded` then bails because `_cart.allItemsFor(...)` is non‑empty (`waiter_order_screen.dart:131‑135`). When the waiter re‑opens the card → order screen → taps Pay Later, `existingBookingId` is non‑null ⇒ the Edit‑Order branch runs `_dispatchToKds(orderId, isEdit: true)` for the *same* items the original `_payLater` already sent ⇒ the kitchen prints a supplemental ticket for items it already has.
*Fix sketch:* flush the cart store **synchronously** (or `await` an immediate flush) after `markDraftAsSent` on a successful booking, the same way the registry flushes commit‑level events.

### B‑13 · `WaiterTablesScreen` mutates the elements of `_tables` on every build · **Low** · `waiter_tables_screen.dart:1173‑1175` (also `:154‑156, :188‑194`)

```dart
final overlaid = t
  ..status = ownerId != null ? TableStatus.occupied : t.status
  ..waiterName = ownerName ?? t.waiterName;
return WaiterTableCard(... table: overlaid, ...);
```
`overlaid` *is* `t`, an element of `_tables`. Once `ownerId != null` writes `occupied`, the `t.status` clause can never write it back to `available` (it's `t.status = t.status`); only `_onLifecycle`'s `released` setState clears it (and that can be dropped — A‑9). `_onMigrate` mutates `_tables` elements too. The `WaiterTableCard` widget itself is read‑only — the problem is the screen permanently overwriting its fetched list.
*Fix sketch:* build a throwaway copy for the card (`TableItem.from(t)..status=…`); keep `_tables` pristine and derive overlays from the registry each build.

### B‑14 · A peer that flickers offline can stay marked offline forever (and `closeConnectionTo` can make a live peer permanently invisible) · **Medium** · `waiter_roster_service.dart:68‑74, 81‑94`, `waiter_controller.dart:1444‑1458`, `waiter_network_service.dart:147‑167, 338‑350`

(a) `RosterService.touch()` refreshes `lastSeen` but **never** changes `status`. A peer that misses ≥3 heartbeats is flipped `offline` by `sweepStale`; if its WS then resumes and it sends only `HEARTBEAT`s (no new `HELLO`), `_handleIncoming` does `roster.touch()` (no notify, no status change) then `case heartbeat: break;` — it never `upsert`s a `status`, so the peer is stuck `offline` in every UI until it happens to send a status‑bearing message. (b) When the sweep flips a peer offline, the controller calls `_net.closeConnectionTo(id)`, which drops the socket **and forgets the address + cancels the reconnect timer** (`waiter_network_service.dart:338‑350`). Recovery then depends on either a fresh mDNS `discoveryServiceFound` re‑emit (Bonsoir caches; it usually won't re‑emit for an unchanged service) or the *peer* re‑initiating — but only the lexicographically‑lower id initiates (`waiter_controller.dart:1118`). So a higher‑id peer that flickers can vanish for the rest of the shift even though it's alive.
*Fix sketch:* in `_handleIncoming`, when an `offline`‑marked peer sends anything, `roster.upsert` it back to a live status (the heartbeat carries `data.status`); and consider re‑arming a reconnect (or re‑resolving via mDNS) for a peer that comes back rather than only `closeConnectionTo`‑ing it.

### B‑15 · `incoming_pickup_banner.dart` — Accept ignores the claim result and the banner doesn't react to a peer's claim; the 12 s timer stomps whatever banner is current · **Medium** · `lib/waiter_module/dialogs/incoming_pickup_banner.dart:23, 75‑95`; also `incoming_call_banner.dart`

`onPressed: () { unawaited(WaiterHaptics.success()); controller.claimTablePickup(req.requestId); messenger.hideCurrentMaterialBanner(); }` — the return value (which is the *already‑claimed* request if a peer beat us, `waiter_controller.dart:913`) is discarded, so this waiter gets the success haptic regardless of who actually got the table. The banner doesn't subscribe to `controller.onPickupUpdate`/`pickupStore`, so it keeps showing the prominent "استلام" button for up to 12 s after a peer has claimed the table. And `Future.delayed(12s, () => messenger.hideCurrentMaterialBanner())` hides *whatever* banner is current then — a later pickup or an incoming‑call banner gets cut short (both helpers share one `ScaffoldMessenger` and call `clearMaterialBanners()` on entry). *(The Notifications‑tab pickup row, `waiter_messages_screen.dart:453‑462`, also discards the result but at least re‑renders from `pickupStore` so the row flips to "claimed by X".)*
*Fix sketch:* check `claimTablePickup`'s return (only success haptic if `claimed.claimedByWaiterId == self.id`); subscribe the banner to `onPickupUpdate` and auto‑hide when the request leaves `isPending`; capture a handle to the specific `MaterialBanner` and only `hide` it if it's still current (token/generation check inside the delayed callback).

### B‑16 · `WaiterOrderScreen` UPDATE_CART KDS preview, `WireMessageType.tableAssign/Release/PaymentStatus`, and `HELLO_ACK` are documented but never sent · **Low (spec drift / dead code)** · `waiter_kitchen_bridge.dart:59‑76`, `waiter_controller.dart`, `network_message.dart`

`WaiterKitchenBridge.updateCart()` (the `UPDATE_CART` live preview `FR‑ORD‑4` mentions) has no caller — the order screen pushes a `TABLE_UPDATE` mesh event on each cart change instead, not a KDS `UPDATE_CART`. `broadcastTableEvent` always sends `WireMessageType.tableUpdate` regardless of the lifecycle kind, so `TABLE_ASSIGN`/`TABLE_RELEASE`/`TABLE_PAYMENT_STATUS` are never emitted (the receive side handles all four identically). `HELLO_ACK` is reserved/unused (a generic `ACK` answers a HELLO). All harmless, but the SRS reads as if they're live; either wire them up or mark them clearly reserved.

### B‑17 · Waiter‑launch path doesn't gate on `branchModule == 'restaurants'` · **Low** · `login_screen.dart:130‑133`, `branch_selection_screen.dart:48‑51`

`isWaiter()` ⇒ `WaiterModuleEntry` with no check that the branch's module is `restaurants`. A WAITER‑role account on a salon branch would land in the restaurant‑style waiter UI. Probably never happens (the backend likely won't assign WAITER to salon staff) but the gate the SRS calls for (§2.5, §3) is missing.
*Fix sketch:* `if (isWaiter() && ApiConstants.branchModule == 'restaurants') WaiterModuleEntry else …` (and decide what a salon‑branch waiter should see).

### B‑18 · Dead code that lies about its own behaviour · **Low** · `lib/waiter_module/dialogs/call_waiter_dialog.dart`, `lib/waiter_module/widgets/waiter_call_bell_button.dart`, `lib/waiter_module/screens/waiter_login_screen.dart`

`CallWaiterDialog`/`WaiterCallBellButton` are never mounted; their header says "the cashier (or a waiter) rings the bell" but `WaiterController.sendMessage` throws `StateError` for any non‑viewer (`waiter_controller.dart:651‑657`), so if ever wired into a waiter screen every ring fails. `WaiterLoginScreen` is never navigated to (entry auto‑signs‑in / falls back to an inline splash) and, if re‑enabled, would race `start()`/`waitlistMeshBridge.attach`. Delete or document.

### B‑19 · `_extractExpectedTotal` regex grabs the *first* parenthesised number in the error message · **Low** · `waiter_billing_service.dart:946‑951`

`RegExp(r'\(([\d.]+)\)').firstMatch(message)` — if a backend validation message ever contains another `(number)` before the authoritative total (e.g. "pays (10) ≠ invoice total (16)"), the retry uses `10`. Fragile string parsing of a localised message.
*Fix sketch:* anchor on the known phrase (`إجمالي الفاتورة`) or take the *last* match.

### B‑20 · HMAC canonicalisation depends on JSON key‑order surviving a decode→encode round‑trip · **Low (fragility)** · `mesh_auth_service.dart:81‑134`

`verifyRaw` reconstructs the signed bytes by `jsonDecode(raw)` → remove `mac` → `jsonEncode`. This only matches the sender's `jsonEncode(msg.toJson())` because Dart preserves map insertion order on both sides *and* nobody re‑serialises the JSON in between (no proxy, no schema migration that changes how the envelope is built, no `\u`‑escaped vs. raw‑UTF‑8 divergence). Works today; one mediator or a `WireMessage` construction change away from silently rejecting every message.
*Fix sketch:* sign over a canonical form you control (sorted keys, or a fixed field order serialised by hand), not "whatever `jsonEncode` happens to produce".

### B‑21 · `_dispatchToKds` unawaited continuation re‑reads `session.self` ⇒ on a hand‑off race an order can be enqueued under the wrong waiter · **Low (narrow)** · `waiter_order_screen.dart:536‑578, 704‑710`

`_payLater` does `unawaited(() async { await _dispatchToKds(orderId: …); }())`; `_dispatchToKds` then reads `final me = widget.controller.session.self;` — if a sign‑out + new sign‑in happened in the gap (would require ending the shift within milliseconds of tapping Pay Later, and the order screen would normally be gone by then), the enqueued outbox entry carries the new waiter's `waiter_id`. Very narrow, but worth noting alongside the (correct) `clearAll()` outbox wipe.

### B‑22 · `WaiterPickupStore` isn't persisted ⇒ after a waiter force‑kill the "claimed by me" feed and HELLO‑replay are lost · **Low** · `waiter_pickup_store.dart` (no persistence by design), `waiter_controller.dart:1460‑1488`

`FR‑PU‑6`: on HELLO each waiter replays its own claimed pickups. After a force‑kill the store is empty, so there's nothing to replay; the cashier (if it also restarted) won't see "claimed by X" in its feed. The `assigned` registry row (persisted for real waiters) does get re‑pushed on HELLO, so the *table* still shows occupied‑by‑X — only the pickup *feed* entry is lost. Acceptable, but a deviation from the literal FR‑PU‑6 guarantee.

---

## Part C — Spec ⇄ code discrepancies (where the SRS and the code disagree)

| # | SRS says | Code does | Which is right? |
|---|---|---|---|
| C‑1 | FR‑TBL‑2: lifecycle kinds are `assigned/released/updated/paymentPending/paid` | there's a 6th, `takingOrder` (`waiter_table_event.dart:5‑12`, wire `'taking_order'`), used everywhere | **Code.** Update the SRS to list 6 kinds. |
| C‑2 | FR‑CTL‑7 / NFR‑USE‑3: incoming‑call **sound** suppressed while composing an order | only the *pickup* sound is suppressed; the `waiterCall` sound (and banner) play unconditionally (`waiter_controller.dart:1194‑1207`, `waiter_home_screen.dart:80‑83`) | **SRS.** Fix the code (B‑9). |
| C‑3 | FR‑PU‑3: "the UI never reverts to an older claimer" | `markClaimed` reverts to whichever claim has the earlier *device‑clock* timestamp (`waiter_pickup_store.dart:86‑95`) | Ambiguous wording; the *intent* is "deterministic convergence" — implement it via wire‑arrival/Lamport order, not wall‑clock (B‑7). |
| C‑4 | FR‑ORD‑4: "`UPDATE_CART` may be pushed as a live preview while editing" | `WaiterKitchenBridge.updateCart()` exists but is never called (B‑16) | "may" — but the SRS reads as if it's used; clarify. |
| C‑5 | FR‑NET‑8 / NFR‑SEC‑4: config messages "only honoured **from** … viewer sessions" | receive side checks *our* role, not the sender's (B‑2) | **SRS.** Fix the code. |
| C‑6 | §2.5 / §3: waiter UI valid only for `branchModule == 'restaurants'` | launch path doesn't check it (B‑17) | **SRS.** Add the gate. |
| C‑7 | FR‑PU‑6: "On first HELLO each waiter shall replay its own claimed pickups" | true while running; impossible after a force‑kill (store not persisted, B‑22) | minor — note the caveat in the SRS or persist the store. |
| C‑8 | FR‑BILL‑2: total = `round2(subtotal·(1+rate))`, `taxAmount = round2(subtotal·rate)`, using `ApiConstants.digitsNumber` | implemented as stated (`waiter_billing_service.dart:92‑102`) — **verify** the cashier uses the same `digitsNumber` and the same `round2` of `subtotal·(1+rate)` (not `subtotal + taxAmount`) so the two never disagree by a rounding cent | likely OK; make it a regression test (T‑BILL‑1). |

---

## Part D — Checked and found OK (so the next pass doesn't re‑investigate)

- **getIt wiring** (`locator.dart:122‑151`): all `registerLazySingleton`, dependency
  order fine (every dep is itself a lazy `getIt<>` lookup; `DisplayAppService` /
  `ConnectivityService` registered before the waiter block), nothing constructed twice
  (`registerIfNeeded` guard), `allowReassignment` only matters on hot restart.
- **Boot order** (`waiter_module_entry.dart:66‑129`): session.initialize → configStore.initialize
  → outbox.initialize → profile refresh → auto sign‑in → (async) NearPay hydrate →
  reapply KDS endpoint → `controller.start()` → waitlist init + bridge attach. Matches
  `FR‑SES‑1`/`FR‑SES‑6`/`FR‑SES‑7`.
- **`start()` single‑flight + partial‑start unwind** (`waiter_controller.dart:294‑441`):
  `_starting` future is joined by concurrent callers; `startGen` snapshot + `_tearDownPartialStart`
  on a mid‑flight `stop()`/session bump; commits `_running = true` only after success.
- **`_handleIncoming` emit‑after‑dispose guard**: `if (!_running) return;` at the top
  (`waiter_controller.dart:1128`); all `StreamController.add`s sit behind it.
- **HELLO timeout / dedup / HMAC ordering** (`waiter_network_service.dart`): inbound‑HELLO
  5 s timeout is armed (`:191‑200`) and cancelled on HELLO (`:238`); 512‑id LRU evicts the
  oldest (`:225‑233`); `auth.verifyRaw(raw)` runs **before** parse/dedup/handle (`:211‑214`);
  constant‑time MAC compare (`mesh_auth_service.dart:141‑148`); pre‑login "accept unsigned"
  window closes the moment `_key != null` on both sender and receiver; key cleared on
  logout/branch‑switch (`clearSessionStores` → `MeshAuthService.clear()`).
- **`closeConnectionTo` forgets the address** and cancels the reconnect timer before
  dropping the conn, so a stale post‑branch‑switch IP can't reconnect (`waiter_network_service.dart:338‑350`)
  — *but* see B‑14(b) for the live‑peer side effect.
- **Outbox**: single‑writer mutex (`_runLocked`) serialises enqueue vs. flush; progress
  persisted after each successful send; mid‑flush KDS‑drop aborts cleanly and keeps the
  rest; `_retries >= 10` drops the poison entry; `clearAll()` wipes it on signout
  (`FR‑ORD‑6..9`). One residual: a force‑kill between `sendNewOrder` returning and the
  per‑entry `_write` can resend one order (the `idempotency_key` isn't consumed by the
  KDS yet) — acknowledged by `FR‑ORD‑7` / Appendix A4.
- **`clearSessionStores` coverage** (`waiter_controller.dart:252‑292`): messages, pickup
  store, table registry (incl. disk, awaited), roster, cart store, **outbox**, billing
  caches, BranchService caches, mesh MAC key — all wiped; printer list / KDS endpoint
  intentionally **not** wiped. Matches `FR‑SES‑10` (modulo the persist‑tail race, B‑5).
- **Migration** (`waiter_controller.dart:959‑1075`, `waiter_tables_screen.dart:467‑622`):
  cashier or *owning* waiter only; `old == new` no‑op; owner moves cart (drafts+sent+guests),
  broadcasts `released` for old then `assigned` for new carrying `guestCount`/`total`/
  `itemCount`/`items` **and the pay‑later `orderId`**; re‑establishes `paymentPending` on
  the new id; non‑owners just emit on the stream; waiter‑driven path PATCHes the backend
  first and rolls back if the mesh guard rejects. Matches `FR‑MIG‑1..3`.
- **Notifications feed / mark‑read** (`waiter_messages_screen.dart`): does **not** call
  `markAllRead` in `initState` (delegated to `WaiterHomeScreen`, `:33‑41`); feed shows
  pending broadcasts with Accept, accepted ones with "تم الاستلام بواسطة X" / no Accept,
  legacy directed messages with no Accept; unread badge counts `!read && !isAccepted`.
  Matches `FR‑MSG‑4`.
- **Config sync**: send side viewer‑gated; version‑gated + source‑id tiebreak on receive;
  persisted; KDS endpoint re‑applied to the live `DisplayAppService` on resume; cashier
  re‑pushes on its own config mutations and on `DisplayAppService` changes (debounced).
  Matches `FR‑CFG‑1..3` — except the receive‑side sender‑is‑viewer check (B‑2).
- **Backend pay‑later reconcile** (`waiter_controller.dart:443‑556`): ≤4×50, fire‑and‑forget,
  session‑generation bail, `skipGlobalAuth` so a 401 doesn't tear down the session,
  injection‑only, dedups booking ids across pages, filters on
  unpaid + not‑cancelled + ours (`cashier_name == self.name`) + has table id + not already
  in the registry. Matches `FR‑CTL‑5` / `FR‑BILL‑8`. (One brittleness: the `cashier_name`
  equality is exact‑trim — if the backend stores the name with different
  whitespace/case than `self.name`, nothing is re‑injected.)
- **Waitlist bridge** (per the sub‑agent pass): `attach` idempotent per‑controller;
  every local mutation broadcasts `WAITLIST_EVENT`; remote deltas apply without
  re‑broadcast; HELLO push of a `WAITLIST_SNAPSHOT` only when the local queue is non‑empty;
  subs cancelled on detach. Residual: `applySnapshot` is last‑write‑wins per‑entry with no
  timestamp gate (acknowledged in‑code), so a late joiner's snapshot could clobber a change
  made in the tiny join‑window — low probability.
- **Receipt path**: the waiter routes through `WaiterPrintDispatcher.buildCashierReceiptData`
  → `ReceiptBuilderService.build(...)` → `InvoicePrintWidget` / `PrinterService.printReceipt`
  — the shared cashier path; no new printing logic. `_BillPreview` reads
  `printerLanguageSettings.{primary,secondary,allowSecondary}`, the same trio the cashier's
  `InvoiceDetailsDialog` uses. Matches `FR‑BILL‑6`. (Residual: `WaiterPrintDispatcher` has
  no session‑generation guard, so a fire‑and‑forget print queued in one shift could land
  after `clearSessionStores()` — harmless for receipts, mentioned for completeness.)

---

## Part E — Cross‑cutting Dart hazards observed

- **`BuildContext` / `mounted` across `await`** that loses results: B‑1 (`processBill`),
  and the general pattern in `waiter_order_screen.dart` / `table_details_dialog.dart` where
  the success side effects sit after a `mounted` check that fails on route pop.
- **Un‑awaited futures whose failures vanish silently**: `unawaited(_dispatchToKds(...))`,
  `unawaited(_printDispatcher.print*())`, `unawaited(_reconcileFromBackendPayLaterBookings)`,
  `unawaited(getIt<BranchService>().fetchAndCacheBranchReceiptInfo())` — all intentional and
  individually `try`/`catch`‑wrapped at the leaf, so this is mostly fine; B‑21 is the one
  that has a (narrow) data consequence.
- **Debounced persistence with no serialization chain**: `WaiterCartStore._flushPersist`
  (B‑5) — overlapping runs can desynchronise the dual slots.
- **In‑place mutation of "borrowed" objects**: B‑13 (`_tables` elements).
- **`==`/`hashCode` on a model used in collections**: `Waiter` is `==` by `id` only
  (documented); every map that holds waiters keys on `String` (`roster._byId`,
  `pickupStore._byId`, `registry._byTableId`), never on `Waiter` — no mismatch. OK.
- **Streams/timers cleanup**: `WaiterController.dispose()` closes all 9 `StreamController`s
  and cancels subs/timers even without a prior `stop()`; `WaiterNetworkService.dispose()`
  cancels reconnect/hello timers, clears the LRU, drops conns, closes `_incoming`;
  `WaiterDiscoveryService.dispose()` cancels the sub and stops broadcast/discovery. The
  registry/cart `_persistDebounce` timers are never cancelled (their owners are getIt
  singletons that are never disposed) — benign.

---

*End of findings. The companion document `WAITER_MODULE_TEST_PLAN.md` turns each FR area
and each finding above into runnable manual / integration test cases.*
