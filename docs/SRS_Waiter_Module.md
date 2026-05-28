# Software Requirements Specification — Waiter Module

**Product:** Hermosa POS (Cashier App)
**Sub‑system:** Waiter Module (`lib/waiter_module/`)
**Document version:** 1.0
**Date:** 2026‑05‑12
**Status:** Reverse‑engineered from the current implementation (`main`)

---

## 1. Introduction

### 1.1 Purpose
This document specifies the functional and non‑functional requirements of the **Waiter Module** — the in‑app, tablet‑based waiter terminal that ships inside the Hermosa POS application. It is intended for developers, QA, and product owners who maintain or extend the module. It describes what the module does today; where behaviour is intentionally deferred to a later phase it is marked **(Phase 2)**.

### 1.2 Scope
The Waiter Module turns a staff tablet (typically a Sunmi device) into a roaming order terminal that:

- discovers other staff devices on the same Wi‑Fi/LAN without any server configuration;
- shows a live floor plan of all tables and who owns each one;
- lets a waiter take a dine‑in order, send it to the Kitchen Display System (KDS) / kitchen printer, and queue it offline if the kitchen link is down;
- lets a waiter close out a table by creating a booking + invoice (cash or NearPay card) and printing the customer receipt;
- mirrors and participates in the shared **waitlist** (queue of waiting parties);
- exchanges presence, table‑lifecycle, "pickup" (table hand‑off) and chat/call notifications with the cashier and other waiters over an authenticated LAN mesh.

It runs **only for branches whose module is `restaurants`** (it is launched from the cashier login / branch‑selection flow when the signed‑in user has the *waiter* role, and from `branch_selection_screen.dart`). It is **out of scope** for salon branches.

The module re‑uses cashier infrastructure where possible (`DisplayAppService` for KDS traffic, `PrintersTabView` for printer setup, `OrderService`/`BranchService`/`AuthService` for backend calls, the NearPay stack for card payments, `ReceiptBuilderService` for receipts).

### 1.3 Definitions, acronyms, abbreviations

| Term | Meaning |
|---|---|
| **Waiter** | A staff identity advertised on the LAN. `id` is a stable per‑device UUID; `name` comes from the backend user profile. |
| **Viewer** | A non‑interactive mesh participant (the cashier). Identified by the `viewer-` id prefix. Listens to waiter broadcasts and pushes config, but is excluded from "call a waiter" lists and cannot take orders. |
| **Mesh / LAN protocol** | The peer‑to‑peer WebSocket network the module forms between devices on the same branch. |
| **Wire message** | A single JSON envelope on the mesh (`WireMessage`), HMAC‑signed via `MeshAuthService`. |
| **KDS** | Kitchen Display System — the screen in the kitchen that receives orders. Reached over the cashier's existing `DisplayAppService` WebSocket. |
| **Pickup ("استلام")** | Uber‑style table hand‑off: the cashier broadcasts "table N needs a waiter", the first waiter to tap *accept* claims it. |
| **Table migration** | Moving a seated party (cart, booking id, registry state) from one table to another. |
| **Pay‑later booking** | A booking created on the backend that has not yet been paid; the table stays "occupied / payment pending" until an invoice is created. |
| **Outbox** | Local persisted queue of KDS orders that could not be delivered because the KDS socket was down. |
| **mDNS / Bonsoir** | Multicast DNS service discovery (`_hermosa-waiter._tcp`) used to find peers. |
| **Roster** | The in‑memory list of currently‑known peers and their presence. |

### 1.4 References
- IEEE Std 830‑1998 (SRS structure, adapted).
- Source: `lib/waiter_module/**`, `lib/locator.dart`, `lib/screens/login_screen.dart`, `lib/screens/branch_selection_screen.dart`, `lib/screens/table_management_screen.dart`.
- Related design notes: `BOOKING_SETTINGS_RAW_RESPONSE.json`, the `*.har` capture files at repo root.

### 1.5 Overview
Section 2 gives the product context, actors, and constraints. Section 3 enumerates functional requirements grouped by capability. Section 4 covers external interfaces. Section 5 covers non‑functional requirements. Section 6 lists data entities. Section 7 records assumptions and open items.

---

## 2. Overall Description

### 2.1 Product perspective
The Waiter Module is a self‑contained feature package inside the Flutter app. Its services are registered in the global `getIt` locator (`WaiterSessionService`, `WaiterRosterService`, `WaiterMessageStore`, `WaiterNotificationService`, `WaiterCartStore`, `WaiterTableRegistry`, `WaiterConfigStore`, `WaiterPickupStore`, `WaiterKitchenBridge`, `WaiterOrderOutbox`, `WaiterController`, `WaiterBillingService`, `WaiterPrintDispatcher`). The single UI entry point is `WaiterModuleEntry`.

Two distinct runtime roles share the same code:
- **Waiter role** — the full UI (`WaiterHomeScreen` with Tables / Notifications / Profile tabs). Reached from the cashier login flow when the authenticated user is a waiter.
- **Viewer role (cashier)** — the cashier's table‑management screen attaches a `WaiterController` in *viewer* mode (`ensureViewer`) so it can mirror waiter table state, send pickup requests, send cashier→waiter messages, and push printer/KDS config. No separate "waiter app" UI is shown.

```
            ┌───────────────────────────────────────────────┐
            │                 Branch LAN                    │
   Cashier  │  ┌──────────┐   mDNS + WebSocket mesh         │
  (viewer)──┼─►│ Waiter A │◄──────────────────────────────► │
            │  └──────────┘        ▲          ▲             │
            │  ┌──────────┐        │          │             │
            │  │ Waiter B │◄───────┘          │             │
            │  └──────────┘                   │             │
            └───────────────┬─────────────────┼─────────────┘
                            │                 │
                       KDS / kitchen      Hermosa backend
                       printer (DisplayAppService)  (HTTPS API)
```

### 2.2 Product functions (summary)
1. Auto sign‑in and shift lifecycle.
2. Peer discovery, presence and roster.
3. Authenticated LAN mesh transport.
4. Live table floor plan with ownership and status.
5. Order composition, KDS dispatch, and offline outbox.
6. Billing: booking creation, cash / NearPay card payment, receipt printing.
7. Table pickup (hand‑off) flow.
8. Table migration.
9. Shared waitlist participation.
10. Cashier↔waiter notifications, calls, and chat.
11. Cashier‑pushed printer / KDS configuration sync.
12. Per‑device printer settings (shared with cashier UI).

### 2.3 Actors / user classes
- **Waiter** — primary user; takes orders, closes tables, responds to pickups and calls.
- **Cashier (viewer)** — initiates pickups, migrations, and messages; closes tables too; owns canonical printer/KDS config.
- **Kitchen / KDS** — passive consumer of `NEW_ORDER` / `UPDATE_CART` / `ORDER_CANCEL` messages; requires no changes (waiter uses the cashier wire format).
- **Hermosa backend** — source of truth for the user profile, branch settings, tax config, payment methods, products, bookings, and invoices.
- **Rogue LAN device** — explicit adversary in the threat model (see §5.4).

### 2.4 Operating environment
- Flutter app on Android (Sunmi POS hardware) and iPad (subset — note NFC/NearPay availability differs by platform).
- Devices share one Wi‑Fi network/subnet with mDNS multicast permitted.
- Backend reachable over HTTPS; KDS reachable over the LAN via `DisplayAppService`.
- Persistent local storage via `SharedPreferences`.

### 2.5 Design & implementation constraints
- **No printing logic may be changed without explicit approval** — the module must route receipts through the shared `ReceiptBuilderService` / existing print stack.
- **Restaurant‑only**: must not touch salon module code; conversely the waiter UI is only valid for `branchModule == 'restaurants'`.
- Mesh transport is plain `ws://` (no TLS) because Sunmi devices have no certificate‑provisioning pipeline; authenticity is provided at the application layer (HMAC).
- Wire protocol version is `1`; messages from a higher version are dropped rather than misinterpreted.
- Backend role restrictions may forbid a waiter from listing bookings — best‑effort calls must use `skipGlobalAuth` so a 401 does not tear down the session.

### 2.6 Assumptions and dependencies
- `ApiConstants.branchId` / `sellerId` are populated by `AuthService` before the controller starts (a brief boot race is tolerated and degrades gracefully).
- The cashier on the same branch derives an identical mesh key from `(branchId, sellerId)` without any handshake.
- Bonsoir/mDNS works on the device; if it fails, the module degrades to "alone on the LAN" rather than crashing.

---

## 3. Functional Requirements

> IDs use the form **FR‑<area>‑<n>**. "shall" = mandatory.

### 3.1 Session & shift lifecycle (`WaiterModuleEntry`, `WaiterSessionService`)

- **FR‑SES‑1** On entry the module shall hydrate the session for `ApiConstants.branchId`, initialise the config store, and initialise the outbox **before** bringing the mesh up.
- **FR‑SES‑2** The module shall refresh the backend user profile on every entry (cold start included). If the refresh fails it shall fall back to the cached profile.
- **FR‑SES‑3** The waiter's display name shall be derived from the profile in priority order: `fullname[currentLanguage]` → `fullname['ar']` → `fullname['en']` → first non‑empty `fullname` value → `name` → email local‑part → `mobile`. If none resolve, a retry splash shall be shown instead of the home screen.
- **FR‑SES‑4** The module shall auto‑sign‑in using the resolved name, replacing any stale stored name. No "type your name" form is presented on the happy path (the legacy form remains only as a fallback).
- **FR‑SES‑5** A stable per‑device UUID (`waiter_device_id`) shall be minted once and reused across restarts as the waiter `id`. Name and branch are persisted under `waiter_name` / `waiter_branch_id`.
- **FR‑SES‑6** On a returning signed‑in session the module shall: re‑apply the last cashier‑pushed KDS endpoint, resume the shift (`WaiterController.start()`), initialise the waitlist service, and attach the waitlist mesh bridge.
- **FR‑SES‑7** The module shall bootstrap NearPay config (`hydrateNearPayConfig`) concurrently with the rest of boot, mirroring the cashier's login‑time behaviour, so a waiter on a NearPay‑enabled branch gets the in‑app card flow.
- **FR‑SES‑8** Ending the shift ("end shift" in Profile) shall broadcast `WAITER_LEAVE`, sign the waiter out (clearing `waiter_name`/`waiter_branch_id` atomically), and clear all session‑scoped stores (see FR‑SES‑10) before any new sign‑in can race the disk wipe.
- **FR‑SES‑9** Switching branch (cashier‑viewer case) shall tear down the mesh, clear session stores, assign the new viewer identity, and restart so the mDNS advertisement carries the new branch id.
- **FR‑SES‑10** "Clear session stores" shall wipe: messages, pickup store, table registry (incl. disk), roster, cart store, **order outbox** (so the next waiter on the device never ships the previous one's queued orders under their identity), billing caches (pay methods + tax), `BranchService` session caches, and the mesh MAC key. It shall **not** clear the printer list / KDS endpoint (cashier‑owned, survives waiter turnover).
- **FR‑SES‑11** The waiter may change availability status to `free` / `busy` / `on_break` (and implicitly `offline`); the change shall be broadcast (`WAITER_STATUS`).

### 3.2 Peer discovery & roster (`WaiterDiscoveryService`, `WaiterRosterService`)

- **FR‑DISC‑1** Each device shall advertise itself via mDNS as `_hermosa-waiter._tcp` with TXT records `id, name, branch_id, status` and the bound WebSocket port.
- **FR‑DISC‑2** Each device shall browse the same service type and emit "found"/"lost" events for peers.
- **FR‑DISC‑3** Peers on a **different** `branch_id` shall be ignored at discovery time.
- **FR‑DISC‑4** To avoid both ends dialling each other, the device with the **lexicographically lower** `id` initiates the outbound WebSocket connection.
- **FR‑DISC‑5** The roster shall track `lastSeen` per peer. Any inbound mesh message (not just heartbeats) refreshes `lastSeen`.
- **FR‑DISC‑6** A heartbeat (`HEARTBEAT`) shall be broadcast every 15 s. A stale sweep shall run every 10 s and mark peers not seen for >45 s as offline; the sweep shall also force‑close the half‑dead socket to that peer so the next HELLO lands on a fresh connection.
- **FR‑DISC‑7** Roster identity is the device id only — two `Waiter` snapshots with the same id are equal regardless of status/host/lastSeen; call sites that need the newer snapshot must overwrite by key.

### 3.3 LAN mesh transport (`WaiterNetworkService`, `MeshAuthService`, `network_message.dart`)

- **FR‑NET‑1** Each device shall bind an `HttpServer` (preferred port `47231`, then scan ±20, then OS‑assigned) that upgrades inbound requests at path `/waiter` to WebSockets, and shall open outbound WebSockets to discovered peers; `incoming`/`broadcast`/`sendTo` shall be direction‑agnostic.
- **FR‑NET‑2** A minimal HELLO/ACK handshake shall occur on every new connection so each side locks the peer id to the channel. An inbound channel that does not send HELLO within 5 s shall be closed (FD‑exhaustion defence).
- **FR‑NET‑3** Outbound connections shall auto‑reconnect (3 s backoff, coalesced) using the last known host:port after a drop, until the roster sweep explicitly forgets the peer (`closeConnectionTo`).
- **FR‑NET‑4** Every wire message carries: `v` (=1), `type`, `id` (uuid), `ts` (epoch ms), `sender_id`, `sender_name`, `branch_id`, `data`. Messages with `v` > 1 shall be dropped; missing `v` is treated as v1.
- **FR‑NET‑5** Inbound messages shall be de‑duplicated via a bounded LRU of the last 512 message ids (handles WS flap / multicast bounce → no duplicate kitchen tickets, phantom payment‑pending, or double pickup‑acks).
- **FR‑NET‑6** Self‑loop messages (`sender_id == self.id`) shall be ignored. Messages whose envelope `branch_id` disagrees with the local branch shall be dropped (defence against a stale cached peer IP after a branch switch).
- **FR‑NET‑7 (Mesh auth)** Every outgoing message shall be HMAC‑SHA256 signed with a per‑branch key derived from a compile‑time pepper + `branchId:sellerId`. Every incoming message shall be verified; a missing/invalid MAC → silent drop, *before* parsing or dedup. During the pre‑login boot window (no key yet) both sides accept unsigned messages so a freshly‑launched mesh is not dead; once hydrated, unsigned messages are rejected. MAC comparison shall be constant‑time. The key shall be cleared on logout/branch switch.
- **FR‑NET‑8 (Anti‑spoof per type)**:
  - `WAITER_CALL_ACCEPTED`: `data.waiter_id` must equal envelope `sender_id`.
  - `TABLE_PICKUP_REQUEST` / `TABLE_PICKUP_CANCELLED`: sender id must start with the `viewer-` prefix (only the cashier may issue/cancel pickups).
  - `TABLE_PICKUP_CLAIMED`: `data.waiter_id` must equal `sender_id`.
  - Config messages (`CONFIG_KITCHEN_PRINTERS`, `CONFIG_KDS_ENDPOINT`, `CONFIG_SYNC_REQUEST` responses): only honoured from / by viewer sessions.
- **FR‑NET‑9** The full wire vocabulary is: `HELLO`, `HELLO_ACK` (reserved), `HEARTBEAT`, `WAITER_ANNOUNCE`, `WAITER_STATUS`, `WAITER_LEAVE`, `WAITER_CALL`, `WAITER_MESSAGE`, `WAITER_CALL_ACCEPTED`, `TABLE_ASSIGN`, `TABLE_RELEASE`, `TABLE_UPDATE`, `TABLE_PAYMENT_STATUS`, `NEW_ORDER`, `UPDATE_CART`, `ORDER_EDIT`, `ORDER_CANCEL`, `CONFIG_KITCHEN_PRINTERS`, `CONFIG_KDS_ENDPOINT`, `CONFIG_SYNC_REQUEST`, `TABLE_PICKUP_REQUEST`, `TABLE_PICKUP_CLAIMED`, `TABLE_PICKUP_CANCELLED`, `TABLE_MIGRATE`, `WAITLIST_EVENT`, `WAITLIST_SNAPSHOT`, `ACK`, `ERROR`.

### 3.4 Mesh coordination (`WaiterController`)

- **FR‑CTL‑1** `start()` shall be single‑flight (concurrent callers join the same future) and shall, in order: rehydrate the table registry & cart store from disk (real waiters only, scoped by `branch+name`), reconcile orphan pay‑later bookings from the backend (fire‑and‑forget, ≤4 pages × 50), prewarm branch receipt info + tax config, derive the mesh key, start the WS server, start mDNS, wire subscriptions, then start heartbeat/sweep timers and announce self. If any step throws, partially‑started resources shall be released.
- **FR‑CTL‑2** If `stop()` / a session‑generation bump occurs during an in‑flight `start()`, the controller shall unwind and remain stopped (no silent resurrection).
- **FR‑CTL‑3** On first HELLO from a peer the controller shall push a snapshot of every table it currently owns (as `TABLE_UPDATE`) to that peer, and (waiter side) replay its own claimed pickups, so late joiners converge without waiting for the next mutation.
- **FR‑CTL‑4** On every HELLO the controller shall emit `onPeerHello(senderId)`; the cashier‑viewer side uses this to push current printer + KDS config snapshots (version‑gated for idempotency).
- **FR‑CTL‑5 (Backend reconcile)** On a real‑waiter start, the controller shall page the backend's open bookings and inject any pay‑later booking that (a) is unpaid & not cancelled, (b) was created by *this* waiter (`cashier_name` == self name), (c) has a table id, (d) is not already in the registry — re‑broadcasting it as a `paymentPending` `TABLE_UPDATE` so peers converge. Injection only; never overwrite. Must abort if the session generation changes mid‑page. A 401 must not tear down the session.
- **FR‑CTL‑6** The controller shall expose streams for: incoming calls, table events (with `fromSelf` flag), peer HELLO, config‑sync requests, pickup requests, pickup updates, table migrations, waitlist events (with `fromSelf` flag), and waitlist snapshots.
- **FR‑CTL‑7** The controller shall track `activeOrderingTableId` (set on entering the order screen for a table, cleared on exit). While set, disruptive UI (pickup banner sound, incoming‑call sound) shall be suppressed for that device, but the underlying request shall still be persisted so it surfaces when the order screen is closed.

### 3.5 Table floor plan & registry (`WaiterTablesScreen`, `WaiterTableRegistry`, `WaiterTableCard`)

- **FR‑TBL‑1** The Tables tab shall show a grid of every table in the branch (from `TableService`), overlaying live ownership and status from `WaiterTableRegistry`. While loading it shall show a skeleton grid.
- **FR‑TBL‑2** Table lifecycle kinds shall be: `assigned`, `released`, `updated`, `paymentPending`, `paid` (carried in `TableLifecycleEvent` with table id/number, waiter id/name, and optionally `guestCount`, `total`, `itemCount`, `items`, `orderId`).
- **FR‑TBL‑3** `broadcastTableEvent` shall apply the event to the local registry first, emit a `fromSelf:true` envelope, then broadcast `TABLE_UPDATE`. Inbound `TABLE_ASSIGN/RELEASE/UPDATE/PAYMENT_STATUS` shall apply to the registry before emitting `fromSelf:false`.
- **FR‑TBL‑4** The registry shall persist (disk) for real‑waiter sessions only, scoped by `branch+name+selfId`; viewer sessions do not persist. It shall survive app restart so a lone waiter still sees their tables.
- **FR‑TBL‑5** The cashier's table‑management screen (viewer) shall mirror this state and additionally offer: send a cashier message to a waiter, request a table pickup, and migrate a table.
- **FR‑TBL‑6** A waiter shall be able to open a table to take/continue an order (→ §3.6) and, for a pay‑later table they own, to edit the order or create the invoice (→ §3.7).

### 3.6 Order composition & kitchen dispatch (`WaiterOrderScreen`, `WaiterCartStore`, `WaiterKitchenBridge`, `WaiterOrderOutbox`)

- **FR‑ORD‑1** The order screen shall let the waiter browse products (via `ProductService`), customise items (`ProductCustomizationDialog` — quantity, notes, extras), set guest count, and assemble a per‑table cart.
- **FR‑ORD‑2** The cart store shall hold, per table, draft items, sent items, and guest count, and shall persist drafts to disk (scoped by `branch+name`) so an app kill mid‑composition restores them.
- **FR‑ORD‑3** On entering/leaving the order screen the controller's `activeOrderingTableId` shall be set/cleared (FR‑CTL‑7).
- **FR‑ORD‑4** Sending an order to the kitchen shall use `WaiterKitchenBridge`, which emits the **exact same** `NEW_ORDER` envelope shape the cashier uses (`order_type: dine_in`, items as `{name, quantity, notes, price, extras[]}`, a combined note `Table N • Waiter: X • <note>`), so the KDS needs no changes. `UPDATE_CART` may be pushed as a live preview while editing; `ORDER_CANCEL` / `ORDER_EDIT` follow the cashier schema.
- **FR‑ORD‑5** Sending an order shall also broadcast the corresponding `TABLE_UPDATE` (occupancy, item count, total, order id) so the cashier/peers see the table fill up.
- **FR‑ORD‑6 (Offline outbox)** If the KDS WebSocket is down when an order is sent, the order shall be enqueued in the persisted outbox (`waiter_outbox` key, single JSON array). Each entry carries `order_id, order_number, table_id, table_number, waiter_id, waiter_name, items, total, branch_id, note?, queued_at, idempotency_key`.
- **FR‑ORD‑7** The outbox shall flush automatically when (a) internet connectivity returns or (b) the KDS WebSocket re‑pairs, and once at startup. Flushing shall be single‑writer mutexed against enqueue, shall persist progress after each successful send (crash‑safe), and shall abort mid‑flush if the KDS drops again.
- **FR‑ORD‑8** Each outbox entry has a `_retries` counter; after 10 failed flushes the entry shall be dropped (so one permanently‑broken order can't wedge every reconnect).
- **FR‑ORD‑9** The outbox shall be wiped on waiter signout (FR‑SES‑10).

### 3.7 Billing, payment & receipt (`WaiterBillingService`, `WaiterPrintDispatcher`, payment dialogs)

- **FR‑BILL‑1** The billing service shall read the branch‑enabled payment methods from the user profile (cached per session, refreshed when the order screen opens) and the branch VAT rate from `BranchService`. Caches shall be cleared on signout.
- **FR‑BILL‑2** The displayed/charged total shall be computed as the cashier does: `round2(subtotal × (1 + rate))`, with `taxAmount = round2(subtotal × rate)`, using `ApiConstants.digitsNumber` for rounding precision.
- **FR‑BILL‑3** Closing a table shall (a) build a booking payload from the cart, (b) call `OrderService.createBooking`, (c) for a card payment on a NearPay‑enabled branch, run the in‑app NearPay flow, (d) on success return `{bookingId, invoiceId, invoiceNumber, dailyOrderNumber, paymentMethod, transactionId}`.
- **FR‑BILL‑4** A `WaiterBillResult` may carry `bookingId`/`invoiceId` even on failure (e.g. backend accepted the booking but the card declined); the UI shall use those to retry **without** creating a duplicate booking.
- **FR‑BILL‑5** A successful close shall: broadcast `paymentPending`→`paid` table lifecycle as appropriate, release the table when fully closed, and print the customer receipt.
- **FR‑BILL‑6** Receipt rendering shall go through the shared `ReceiptBuilderService` / existing `InvoicePrintWidget` path so the waiter receipt is byte‑for‑byte consistent with the cashier receipt (branch seller block, tax number, commercial register, logo URL, daily order number). The branch receipt cache shall be prewarmed at controller start. **No new printing logic shall be introduced.**
- **FR‑BILL‑7** The waiter may send the invoice to the customer via WhatsApp (`SendInvoiceWhatsappButton`), reusing the cashier widget.
- **FR‑BILL‑8** Backend‑created pay‑later bookings that have no local trace (created but app died before the local broadcast) shall be recoverable via the start‑time reconcile (FR‑CTL‑5).

### 3.8 Table pickup / hand‑off ("استلام")

- **FR‑PU‑1** Only a viewer (cashier) may broadcast a `TABLE_PICKUP_REQUEST` (table id, table number, optional note); a waiter caller is rejected with a `StateError`.
- **FR‑PU‑2** Every waiter on the LAN shall receive the request: it is recorded in `WaiterPickupStore`, an audible alert plays (suppressed while that waiter is composing an order — FR‑CTL‑7), and a banner is offered (`IncomingPickupBanner`). The cashier records but does not alert (it already sees the card change).
- **FR‑PU‑3** The first waiter to claim wins: `claimTablePickup` records the claim, broadcasts `TABLE_PICKUP_CLAIMED`, and folds in a `TABLE_ASSIGN` (`assigned` lifecycle) so the cashier's tables screen flips to "occupied by X" and the claimer's registry reflects ownership. Later claims for the same request are dropped locally; the UI never reverts to an older claimer.
- **FR‑PU‑4** A cashier may `cancelTablePickup` while still pending; if already claimed, cancel is a no‑op (table stays assigned).
- **FR‑PU‑5** Orphan‑claim recovery: if the cashier restarted while a pickup was in flight, an inbound `TABLE_PICKUP_CLAIMED` whose request is unknown shall synthesise a minimal request record so the card still flips and the claim shows in the feed.
- **FR‑PU‑6** On first HELLO each waiter shall replay its own claimed pickups to the new peer (covers a claim whose original broadcast was dropped during a cashier restart / Wi‑Fi glitch).

### 3.9 Table migration

- **FR‑MIG‑1** A migration may be initiated by the cashier (viewer) or by the waiter that **owns** the source table; a waiter attempting to migrate a table they don't own is rejected. `oldTableId == newTableId` is a no‑op.
- **FR‑MIG‑2** A `TABLE_MIGRATE` event (old/new table id+number, initiator id+name) shall be broadcast. The owner of the old table performs the heavy lifting; other peers just log/observe.
- **FR‑MIG‑3** The owner shall: move the local cart (drafts + sent + guests) to the new table id; broadcast `released` for the old table; broadcast `assigned` for the new table carrying over `guestCount`, `total`, `itemCount`, `items`, **and the pay‑later `orderId`** (so "Create Invoice" on the moved table invoices the original booking, not a new one); and, if the old table was already `paymentPending`, re‑establish that state on the new table id.

### 3.10 Shared waitlist (`WaitlistService`, `waitlistMeshBridge`, `WaitlistSheet`)

- **FR‑WL‑1** The waiter home screen shall expose the shared waitlist (queue of waiting parties) via a sheet, reusing the cashier widgets.
- **FR‑WL‑2** Every local waitlist mutation (added / updated / removed / notified / seated / cancelled) shall ride the mesh as a `WAITLIST_EVENT` (a `WaitlistMeshEvent` carrying its own `kind`); a self‑echo is delivered on the local event stream so other local listeners get a uniform signal.
- **FR‑WL‑3** On a new device joining the mesh, a full `WAITLIST_SNAPSHOT` shall be sent as catch‑up; the receiving service reconciles last‑write‑wins.
- **FR‑WL‑4** A party may be notified via WhatsApp (`WhatsappService` / `WaitlistNotifyDialog`).

### 3.11 Notifications, calls & chat (`WaiterMessagesScreen`, `WaiterMessageStore`, `WaiterNotificationService`)

- **FR‑MSG‑1** A cashier (viewer) may send a directed message to one waiter or a broadcast "call a waiter" (`WAITER_CALL` / `WAITER_MESSAGE`). Waiter‑to‑waiter calls are disabled and hard‑guarded with a `StateError` (sending is allowed only from a viewer session).
- **FR‑MSG‑2** A receiving waiter surfaces a message if it is a broadcast (and the receiver is not a viewer) or addressed to it. A call message plays the call sound and flashes `IncomingCallBanner`.
- **FR‑MSG‑3** The first waiter to *accept* a broadcast call shall broadcast `WAITER_CALL_ACCEPTED`; every device still showing the notification flips it to "تم الاستلام بواسطة X" and hides the accept button. Local copy is updated optimistically.
- **FR‑MSG‑4** The Notifications tab shall show a flat feed of: pending broadcasts (with Accept), accepted broadcasts ("accepted by X", no Accept), and legacy directed messages (no Accept). An unread badge shall be shown on the tab; marking read is owned by `WaiterHomeScreen` (which knows the active tab), not by the screen's `initState`.

### 3.12 Config sync — cashier → waiter (`WaiterConfigStore`)

- **FR‑CFG‑1** The cashier owns the canonical kitchen‑printer list and KDS host/port. It shall push `CONFIG_KITCHEN_PRINTERS` and `CONFIG_KDS_ENDPOINT` to each waiter on HELLO and on every cashier‑side mutation; waiters never produce authoritative config.
- **FR‑CFG‑2** The config store shall version‑gate incoming payloads (repeated pushes are idempotent) and persist the latest snapshots so a cold‑start waiter has them before the first incoming `NEW_ORDER`.
- **FR‑CFG‑3** On signed‑in resume the module shall re‑apply the stored KDS endpoint to the live `DisplayAppService`.
- **FR‑CFG‑4 (Phase 2)** `CONFIG_SYNC_REQUEST` (waiter‑initiated "refresh config") is reserved; the happy path relies on push‑on‑HELLO.
- **FR‑CFG‑5 (Phase 2)** The synced printer snapshot is stored but not yet consulted by any print path; direct‑print‑from‑waiter for kitchen tickets is future work.

### 3.13 Per‑device printer settings (`WaiterPrinterSettingsScreen`)

- **FR‑PRN‑1** The waiter shall have a printer‑settings hub reachable from the Profile screen with two tabs: "الإعدادات" (printer list with full add / edit / test / remove via the shared `PrintersTabView`) and "اللغة" (primary / secondary invoice language).
- **FR‑PRN‑2** The screen shall reuse the cashier's printer add/edit dialogs and the device/category/kitchen route registries verbatim so the two modules stay consistent (IP, port, paper width, role, Bluetooth address, copies).

---

## 4. External Interface Requirements

### 4.1 User interfaces
- **`WaiterModuleEntry`** — boot/splash → routes to home or retry splash.
- **`WaiterHomeScreen`** — bottom‑nav shell: Tables / Notifications / Profile, plus incoming‑call and incoming‑pickup banners.
- **`WaiterTablesScreen`** — table grid, table‑details dialog, order entry, edit‑order, create‑invoice, waitlist sheet, assign banner.
- **`WaiterOrderScreen`** — product browser, customization dialog, cart, guest count, send‑to‑kitchen, payment tender dialog, receipt print, WhatsApp send.
- **`WaiterMessagesScreen`** — notifications feed with Accept actions.
- **`WaiterProfileScreen`** — status chip, end shift, printer settings link.
- **`WaiterPrinterSettingsScreen`** — printers + language tabs.
- **`WaiterLoginScreen`** — legacy fallback name‑entry form only.
- Localisation: Arabic primary (default user‑visible strings), with the app's multi‑language service in effect.

### 4.2 Hardware interfaces
- Sunmi POS thermal printer(s) / network printers via the existing print stack.
- NearPay card reader / SDK (where the platform & branch support it).
- Wi‑Fi NIC for the LAN mesh and mDNS.

### 4.3 Software interfaces
- **Backend HTTPS API** via `AuthService` (profile), `BranchService` (branch settings, tax, receipt info), `OrderService` (bookings, invoices, getBookings), `ProductService` (catalogue), `TableService` (tables), `DeviceService` (printer config).
- **KDS** via `DisplayAppService` (`sendOrderToKitchen`, `updateCartDisplay`, connection‑state `Listenable`).
- **NearPay** via `NearPayService` (SDK wrapper), `nearpay/nearpay_service.dart` (JWT helper), `nearpay_bootstrap`, `nearpay_config_service`, `RemoteNearPayDispatcher`.
- **Receipts** via `ReceiptBuilderService` / `InvoicePrintWidget` (shared, single source of truth).
- **Local storage** via `SharedPreferences` (keys: `waiter_device_id`, `waiter_name`, `waiter_branch_id`, `waiter_outbox`, plus registry/cart/config snapshot keys).
- **mDNS** via Bonsoir (`bonsoir` package), service type `_hermosa-waiter._tcp`.

### 4.4 Communications interfaces
- **Transport:** WebSocket over TCP, path `/waiter`, port `47231` (or next free / OS‑assigned). No TLS.
- **Discovery:** multicast DNS‑SD; TXT records `id`, `name`, `branch_id`, `status`.
- **Envelope:** UTF‑8 JSON, fields per FR‑NET‑4, optional top‑level `mac` (HMAC‑SHA256 hex).
- **Protocol version:** `1`.

---

## 5. Non‑Functional Requirements

### 5.1 Performance
- **NFR‑PERF‑1** Heartbeat 15 s; stale sweep 10 s; peer considered offline after 45 s of silence.
- **NFR‑PERF‑2** Inbound‑message dedup window: last 512 ids (bounded LRU).
- **NFR‑PERF‑3** Backend pay‑later reconcile: ≤ 4 pages × 50 rows, fire‑and‑forget, must not delay the table grid.
- **NFR‑PERF‑4** The outbox must handle realistic volumes (hundreds of pending orders) stored as a single JSON array without a new DB schema.
- **NFR‑PERF‑5** Inbound HELLO timeout: 5 s; outbound reconnect backoff: 3 s (coalesced).

### 5.2 Reliability & availability
- **NFR‑REL‑1** Partial‑startup must not leave a wedged controller — any `start()` failure releases brought‑up resources.
- **NFR‑REL‑2** Fire‑and‑forget work captures the session generation on entry and bails on change, so stale reconciles can't resurrect cleared state.
- **NFR‑REL‑3** The module degrades gracefully if mDNS, profile refresh, branch receipt prefetch, or the KDS link fails (logs a warning, continues).
- **NFR‑REL‑4** Crash‑safety: order outbox persists progress after each send; session keys are written before being removed; registry/cart disk wipes complete before any re‑login hydrate races them.
- **NFR‑REL‑5** Reconnect logic re‑establishes peer links autonomously after transient Wi‑Fi drops for the rest of the shift.

### 5.3 Consistency
- **NFR‑CON‑1** Table state converges across all peers via apply‑locally‑then‑broadcast plus push‑on‑HELLO snapshots; `fromSelf` flags prevent double‑processing of self‑echoes.
- **NFR‑CON‑2** Pickup claims are last‑write‑loses (first claim wins); waitlist reconciliation is last‑write‑wins.
- **NFR‑CON‑3** Waiter‑computed totals/taxes must match what the cashier would compute for the same cart.
- **NFR‑CON‑4** Receipts produced by the waiter must match the cashier's receipt for the same invoice.

### 5.4 Security
- **NFR‑SEC‑1 (Threat model — protects against):** opportunistic LAN guests forging messages, MITM injection on the same network, cross‑branch replay (key includes `branchId`+`sellerId`).
- **NFR‑SEC‑2 (Does NOT protect against):** an attacker possessing the APK (the pepper is compile‑time), replay within the dedup window, a compromised legitimate waiter device. Full E2E confidentiality would require `wss://` + cert management, which is not viable on Sunmi devices today.
- **NFR‑SEC‑3** Per‑message HMAC verification happens before parsing/dedup/handling; MAC compare is constant‑time; the key is dropped on logout/branch switch; the pepper is bumped on protocol changes.
- **NFR‑SEC‑4** Role/identity enforcement per FR‑NET‑8 (viewer‑only pickup issue/cancel & config push; sender==claimer/accepter checks).
- **NFR‑SEC‑5** Cross‑branch isolation at three layers: mDNS branch filter, controller envelope branch check, and mesh key scope.
- **NFR‑SEC‑6** Best‑effort backend calls during boot use `skipGlobalAuth` so a 401 cannot tear down the freshly established session.

### 5.5 Privacy & data handling
- **NFR‑PRIV‑1** On waiter signout / device hand‑off, all session‑scoped local data (drafts, queued orders, claimed pickups, notifications, registry, billing caches) is wiped so the next waiter on the device never sees or ships the previous waiter's data — protecting revenue/tip attribution.

### 5.6 Maintainability & portability
- **NFR‑MAINT‑1** The module is an isolated package under `lib/waiter_module/`; shared logic (KDS bridge, printer UI, receipts, billing primitives) is re‑used, not forked.
- **NFR‑MAINT‑2** The wire protocol is versioned; envelope changes require a `kWireProtocolVersion` bump and (for key‑derivation changes) a pepper bump.

### 5.7 Usability
- **NFR‑USE‑1** Zero‑config: no manual peer/KDS/printer setup on the waiter device — discovery is automatic and config is pushed by the cashier.
- **NFR‑USE‑2** The waiter is auto‑signed‑in from the backend profile; no name retyping.
- **NFR‑USE‑3** A waiter actively composing an order is not interrupted by pickup/call sounds, but the items still appear in the feed afterwards.

---

## 6. Data Entities (logical)

| Entity | Key fields | Persistence |
|---|---|---|
| `Waiter` | `id` (device UUID, or `viewer-…`), `name`, `branchId`, `status` (`free`/`busy`/`on_break`/`offline`), `host`, `port`, `lastSeen` | Session (name/branch in `SharedPreferences`); roster in memory |
| `WireMessage` | `v`, `type`, `id`, `ts`, `senderId`, `senderName`, `branchId`, `data`, optional `mac` | Transient (LRU of last 512 ids in memory) |
| `TableLifecycleEvent` | `kind` (`assigned`/`released`/`updated`/`paymentPending`/`paid`), `tableId`, `tableNumber`, `waiterId`, `waiterName`, `guestCount?`, `total?`, `itemCount?`, `items?`, `orderId?` | Reflected into `WaiterTableRegistry` (disk for real waiters) |
| `TablePickupRequest` | `requestId`, `cashierId`, `cashierName`, `tableId`, `tableNumber`, `note?`, `claimedByWaiterId?`, `claimedByWaiterName?`, `claimedAt?`, `cancelled` | `WaiterPickupStore` (in memory) |
| `TableMigrateEvent` | `oldTableId`, `oldTableNumber`, `newTableId`, `newTableNumber`, `initiatedById`, `initiatedByName` | Transient |
| `WaiterMessage` | `id`, `fromWaiterId`, `fromWaiterName`, `toWaiterId` (or broadcast id), `toWaiterName?`, `text`, `tableId?`, `tableNumber?`, `isCall`, accepted‑by fields | `WaiterMessageStore` (in memory) |
| `WaitlistMeshEvent` / `WaitlistMeshSnapshot` | `kind` (added/updated/removed/notified/seated/cancelled) + entry payload / full queue | `WaitlistService` |
| Outbox entry | `order_id`, `order_number`, `table_id`, `table_number`, `waiter_id`, `waiter_name`, `items[]`, `total`, `branch_id`, `note?`, `queued_at`, `idempotency_key`, `_retries` | `SharedPreferences` key `waiter_outbox` |
| `SyncedKitchenPrinter` / KDS endpoint | printer id/name/ip/port/type/model/connection/bt/paper/copies/role/kitchen ids/category ids; KDS host+port | `WaiterConfigStore` (persisted snapshot) |
| `Cart` (per table) | draft items, sent items, guest count | `WaiterCartStore` (disk, scoped by branch+name) |
| `WaiterBillResult` | `success`, `bookingId?`, `invoiceId?`, `invoiceNumber?`, `dailyOrderNumber?`, `errorMessage?`, `paymentMethod?`, `transactionId?` | Transient |

---

## 7. Appendix — Open items / future phases

- **A1** Direct‑print‑from‑waiter for kitchen tickets using the synced printer snapshot (`WaiterConfigStore` already stores it but no print path consumes it). **(Phase 2)**
- **A2** Waiter‑initiated config refresh button using `CONFIG_SYNC_REQUEST`. **(Phase 2)**
- **A3** `HELLO_ACK` is reserved but unused; today a HELLO is acknowledged with a generic `ACK`.
- **A4** KDS‑side dedupe could opt into the outbox `idempotency_key` without a stored‑queue migration; currently the flush loop closes the resend window itself.
- **A5** `wss://` transport (E2E confidentiality) blocked on a Sunmi certificate‑provisioning pipeline.

---

*This SRS was derived from the implementation; if code and document disagree, the code is authoritative — update this file.*
