# Waiter Module — Manual & Integration Test Plan

Companion to `WAITER_MODULE_QA_FINDINGS.md`. Test cases are prose (no `*_test.dart`
authored). Each case: **ID · title · preconditions/setup · steps · expected result ·
FR(s) covered · priority**. Priority: **P0** (must pass before ship / smoke), **P1**
(core), **P2** (edge / resilience).

A ⚠️ marks a case that is expected to **fail today** because of a finding in
`WAITER_MODULE_QA_FINDINGS.md` (the finding id is given). Run it anyway — it's the
regression test for the fix.

---

## 0. Setup matrices

Run the P0/P1 suites across these device/topology combinations:

| Matrix | Devices | Notes |
|---|---|---|
| **M1 — lone waiter** | 1 Sunmi waiter, no cashier viewer, no KDS | discovery degrades to "alone on LAN" |
| **M2 — waiter + cashier(viewer)** | 1 Sunmi waiter + 1 cashier on the same restaurant branch | cashier's table‑management screen is the viewer |
| **M3 — 2+ waiters + cashier** | 2 Sunmi waiters + 1 cashier, same branch | contention / convergence cases |
| **M4 — NearPay on** | M2/M3 on a NearPay‑enabled branch | in‑app card flow (Android) / remote dispatch (iPad) |
| **M5 — NearPay off** | M2 on a cash‑only branch | card methods still shown, fail clearly at execution |
| **M6 — iPad waiter** | iPad waiter + Sunmi cashier | note: no local NearPay SDK / no NFC — card goes via `RemoteNearPayDispatcher` |
| **M7 — cross‑branch noise** | M2 + a second device signed into a *different* branch on the same Wi‑Fi | isolation cases |

"KDS" below = the cashier's paired `DisplayAppService` (kitchen display / kitchen
printer). "Force‑kill" = swipe the app away / `adb shell am force-stop`, not a graceful
exit.

---

## 1. Session & shift lifecycle (FR‑SES‑*)

| ID | Title | Setup | Steps | Expected | FRs | Pri |
|---|---|---|---|---|---|---|
| SES‑01 | Cold‑start auto sign‑in | Fresh install, waiter account, M2 | Log in as a WAITER on the restaurant branch (single branch) | Lands directly on `WaiterHomeScreen` with "مرحبا, <profile name>" — no "type your name" form; mesh comes up; cashier sees the waiter in its roster | FR‑SES‑1..6, FR‑DISC‑1 | P0 |
| SES‑02 | Name fallback chain | Profile whose `fullname` has only `en` (no `ar`), app language = ar | Cold start | Display name = `fullname['en']`; if `fullname` empty everywhere, falls to `name` → email local‑part → `mobile` | FR‑SES‑3 | P1 |
| SES‑03 | No usable name ⇒ retry splash | Profile with no `fullname`/`name`/`email`/`mobile`; not previously signed in | Cold start | Inline retry splash ("تعذّر تحميل بيانات النادل…") instead of the home screen; "إعادة المحاولة" re‑runs bootstrap; once the profile resolves, home screen appears | FR‑SES‑3 | P1 |
| SES‑04 | Stale stored name replaced | Device has `waiter_name = "ببب"` from an old login; backend profile name = "Ahmed" | Cold start | Home shows "Ahmed"; mDNS advertises `waiter-Ahmed-…`; cashier roster shows "Ahmed" | FR‑SES‑3, FR‑SES‑4 | P1 |
| SES‑05 | Profile refresh fails ⇒ cached name kept | Signed‑in waiter, kill network, cold start | Boot | Uses the cached profile name, no crash, mesh still comes up; warning logged | FR‑SES‑2 | P1 |
| SES‑06 | Stable device id across restarts | Note `waiter_device_id` (debug log), restart 3× | — | Same id every time; the same `Waiter.id` on the wire | FR‑SES‑5 | P1 |
| SES‑07 | Returning signed‑in resume | Waiter signed in, has a pay‑later table; cashier had pushed a KDS endpoint | Cold start | Shift resumes (controller `start()`), the stored KDS endpoint is re‑applied to `DisplayAppService`, waitlist service initialised + bridged, the pay‑later table card reappears with its Edit‑Order button | FR‑SES‑6, FR‑CFG‑3, FR‑CTL‑1 | P0 |
| SES‑08 | NearPay bootstrap on entry | M4 | Cold start, then immediately Create Invoice → card | NearPay config flag is set, JWT pre‑warmed, SDK init kicked — the first card checkout doesn't fail with "SDK could not be initialized" | FR‑SES‑7 | P1 |
| SES‑09 | Availability status broadcast | M3 | On waiter A: Profile → tap "busy", then "on_break", then "free" | Each change broadcasts `WAITER_STATUS`; waiter B's roster and the cashier's roster show A's status updating live | FR‑SES‑11, FR‑DISC‑5 | P1 |
| SES‑10 | End shift broadcasts LEAVE + clears stores | M2, waiter has a draft cart + (KDS down) a queued outbox order + a notification in the feed | Profile → End Shift → confirm | `WAITER_LEAVE` broadcast (cashier marks the waiter offline); local registry/cart/messages/pickup/outbox/billing caches all wiped (verify on next sign‑in); navigates to LoginScreen; backend token revoked | FR‑SES‑8, FR‑SES‑10, FR‑ORD‑9 | P0 |
| SES‑11 | **Device hand‑off — no leakage** | M2; waiter A signs in, takes table 5 (pay‑later), drafts items on table 7, queues an order while KDS is down, has 2 notifications | A: End Shift → confirm. Then on the *same tablet* sign in as waiter B | B sees: **none** of A's tables on the grid, no drafts on table 7, an empty outbox (no queued order flushed under B's id when KDS returns), an empty notifications feed, and B's own (possibly different) branch's pay‑methods — not A's | FR‑SES‑8, FR‑SES‑10, NFR‑PRIV‑1 | P0 |
| SES‑12 | ⚠️ Hand‑off race vs. disk wipe (B‑5) | Same as SES‑11 but tap "End Shift" while the grid is mid‑flurry of updates (rapidly open/close a table card a few times right before), then immediately sign in as B | B must still see a clean slate; specifically the table registry / cart for `branch+A` must not resurrect on B's hydrate | FR‑SES‑10, NFR‑REL‑4 | P2 |
| SES‑13 | Branch switch (cashier viewer) | Cashier signed into branch X (restaurant), table‑management screen open; sign out, log into branch Y | The waiter controller tears down, clears stores, re‑starts with a new `viewer-…` id, and the mDNS advertisement carries `branch_id = Y`; no branch‑X table state visible | FR‑SES‑9, FR‑NET‑6 | P1 |
| SES‑14 | signOut force‑kill half‑state | Signed‑in waiter; force‑kill the app during "End Shift" (between the `setString('')` and the `remove`) | On next launch: `waiter_name`/`waiter_branch_id` are empty (not stale); the entry shows the retry splash or auto‑signs‑in cleanly — never "stale branch, no name" | FR‑SES‑8, NFR‑REL‑4 | P2 |

---

## 2. Discovery & roster (FR‑DISC‑*)

| ID | Title | Setup | Steps | Expected | FRs | Pri |
|---|---|---|---|---|---|---|
| DISC‑01 | Two devices find each other | M3, both fresh | Bring both online | Each appears in the other's roster within a few seconds; the lexicographically‑lower id initiates the WS; exactly one connection per pair (no duplicate `waiter-…(2)` service) | FR‑DISC‑1..4, FR‑NET‑1 | P0 |
| DISC‑02 | Cross‑branch peer ignored | M7 | Bring the other‑branch device online | It never appears in the restaurant‑branch roster; no WS opened to it | FR‑DISC‑3, FR‑NET‑6 | P0 |
| DISC‑03 | Peer goes silent ⇒ offline ~45 s | M3 | Pull waiter B's Wi‑Fi (don't end its shift) | After ~45 s, A's and the cashier's roster show B as `offline`; B's owned tables stay visible (state retained, just offline) | FR‑DISC‑5, FR‑DISC‑6, NFR‑PERF‑1 | P1 |
| DISC‑04 | ⚠️ Offline peer comes back (B‑14) | Continue DISC‑03 | Restore B's Wi‑Fi; wait 30 s | B re‑connects (HELLO exchanged), B flips back to a live status on A's and the cashier's roster — **not** stuck `offline`; B's owned‑table snapshot re‑pushed on HELLO | FR‑DISC‑5, FR‑DISC‑6, FR‑NET‑3, FR‑CTL‑3, NFR‑REL‑5 | P1 |
| DISC‑05 | mDNS unavailable | M1 with mDNS multicast blocked (or Bonsoir fails) | Cold start | "Alone on the LAN" — no crash, the rest of the app works; the grid loads from `getTables()` | FR‑DISC‑1..2, NFR‑REL‑3 | P1 |
| DISC‑06 | Short device id | Inject a `waiter_device_id` of <6 chars (dev hook) | Cold start | mDNS service name uses the whole id without an out‑of‑range crash | FR‑DISC‑1 | P2 |

---

## 3. Mesh transport & auth (FR‑NET‑*)

| ID | Title | Setup | Steps | Expected | FRs | Pri |
|---|---|---|---|---|---|---|
| NET‑01 | Port fallback | M3 with another process holding :47231 | Bring a waiter online | It binds 47232..47251 or an OS port; the bound port is what mDNS advertises; peers connect to it | FR‑NET‑1, NFR‑PERF‑5 | P1 |
| NET‑02 | Forged / unsigned message ignored | M2; a script on the LAN sends an unsigned (or wrong‑MAC) JSON envelope to `ws://waiter:port/waiter` | — | The message is dropped *before* parse/dedup — no roster change, no table change, no kitchen ticket, no sound, no log of a handled event (only "dropping unsigned/forged") | FR‑NET‑7, NFR‑SEC‑1..3 | P0 |
| NET‑03 | Cross‑branch replay rejected | M7; capture a valid signed message on branch X, replay it to a branch‑Y device | — | Dropped (envelope `branch_id` mismatch *and* — different branch ⇒ different key — MAC mismatch) | FR‑NET‑6, FR‑NET‑7, NFR‑SEC‑5 | P1 |
| NET‑04 | Future‑protocol message dropped | M2; send a valid‑MAC envelope with `v: 2` | — | Dropped silently; no handler runs | FR‑NET‑4 | P1 |
| NET‑05 | Duplicate message (WS flap / multicast bounce) | M2; deliver the same `NEW_ORDER`/`TABLE_PICKUP_REQUEST`/`TABLE_UPDATE(paymentPending)` envelope twice (same `id`) | — | Handled once: one kitchen ticket, one pickup alert, one `paymentPending` — no double pickup‑ack | FR‑NET‑5, NFR‑PERF‑2 | P1 |
| NET‑06 | Inbound HELLO timeout | M2; open a raw TCP→WS connection to the waiter's `/waiter` and stay silent | — | The waiter closes that socket within ~5 s (FD‑exhaustion defence); a legitimate peer connecting at the same time is unaffected | FR‑NET‑2, NFR‑PERF‑5 | P2 |
| NET‑07 | Pre‑login boot mesh works | M3; have both devices' apps just launched (key not yet hydrated) | Observe the first few seconds | Devices still see each other and exchange HELLO (unsigned accepted during the boot window); once both hydrate, subsequent messages are signed & verified, and any further unsigned message from a now‑hydrated peer is rejected | FR‑NET‑7 | P1 |
| NET‑08 | Outbound reconnect after a drop | M2; on the waiter, drop the TCP conn to the cashier (firewall blip <45 s) | — | The waiter retries every ~3 s (coalesced) using the last known host:port and re‑pairs; after the conn is back, `lastSeen` refreshes and the pair is healthy | FR‑NET‑3, NFR‑REL‑5 | P1 |
| NET‑09 | ⚠️ Sender‑is‑viewer not enforced for config (B‑2) | M3; from waiter B craft a valid‑MAC `CONFIG_KDS_ENDPOINT` envelope (with a non‑`viewer-` `sender_id`) pointing at a bogus host | Send it to waiter A | A must **ignore** it (config is only honoured from a viewer). *Today A applies it and `DisplayAppService` reconnects to the bogus host.* | FR‑NET‑8, NFR‑SEC‑4 | P1 |
| NET‑10 | ⚠️ `sellerId == 0` boot race (B‑4) | Force `start()` to run before `AuthService` writes `ApiConstants.sellerId` (dev hook / slow login) | Bring up a waiter and a cashier on the same branch | They must still talk (same key). *Today the waiter derives `branchId:0`, the cashier `branchId:<real>`, and they HMAC‑reject each other silently.* | FR‑NET‑7, §2.6 | P2 |
| NET‑11 | Anti‑spoof: `WAITER_CALL_ACCEPTED` / `TABLE_PICKUP_CLAIMED` | M2; replay a signed `WAITER_CALL_ACCEPTED` whose `data.waiter_id != sender_id`; same for `TABLE_PICKUP_CLAIMED` | — | Both dropped ("waiter_id != sender_id") | FR‑NET‑8 | P1 |

---

## 4. Table floor plan & registry (FR‑TBL‑*)

| ID | Title | Setup | Steps | Expected | FRs | Pri |
|---|---|---|---|---|---|---|
| TBL‑01 | Grid + skeleton | M1 | Open the Tables tab | Skeleton grid while loading, then every active table in the branch with section tabs; states overlaid from the registry | FR‑TBL‑1 | P0 |
| TBL‑02 | Open a table ⇒ "taking order" on peers | M3 | Waiter A taps table 5 (empty), the order screen opens | Within ~1 s, waiter B's grid and the cashier's screen show table 5 as occupied with the "جاري اخذ الطلب" pill, owner = A | FR‑TBL‑2..3, FR‑ORD‑3 | P0 |
| TBL‑03 | **Leave the order screen without sending ⇒ table returns to free** | Continue TBL‑02 | Waiter A taps the AppBar back arrow (no items added) | Table 5 returns to **free** on A's grid AND on waiter B's grid AND on the cashier's screen — the "جاري اخذ الطلب" pill disappears everywhere | FR‑TBL‑3, A‑2 | **P0** |
| TBL‑04 | ⚠️ Force‑kill while the order screen is open ⇒ table must not stay stuck (A‑1, A‑5, A‑7) | M2; waiter A opens table 5 (empty), waits >1 s | Force‑kill the waiter app. Relaunch it. (Cashier app left running the whole time.) | On the waiter's grid, table 5 is **free** (not "جاري اخذ الطلب"). On the cashier, table 5 is **free** (within a getTables() refresh / reconcile). *Today: stuck on the waiter forever (self‑owned `takingOrder` survives hydrate + reconcile) and on the cashier forever (no `released` ever arrives, cashier never reconciles).* | A‑1..A‑7, FR‑TBL‑3..4 | **P0** |
| TBL‑05 | ⚠️ Wi‑Fi flap at the exact moment of leaving the order screen (A‑2) | M2; waiter A opens table 5 (empty); arrange for the WS to the cashier to drop right as A taps back | Tap back; restore Wi‑Fi 10 s later | The cashier ends up showing table 5 free (either the `released` lands, or a reconcile/age‑out clears it). *Today: the `released` is buffered & lost, the cashier never reconciles ⇒ stuck.* | A‑2, A‑5, FR‑TBL‑3 | P1 |
| TBL‑06 | ⚠️ Open a table, add one item, walk away (A‑6) | M2; waiter A opens table 5, adds 1 item, taps back (does NOT send / pay‑later) | Wait, then pull‑to‑refresh the waiter grid and the cashier screen | Table 5 should *not* remain "occupied · 1 item" forever with no backend booking — either it self‑clears on reconcile, or there's an obvious way to release it. *Today it's stuck on both grids; `reconcileWithBackend` ignores `updated` rows.* | A‑6, FR‑TBL‑3 | P1 |
| TBL‑07 | Send an order ⇒ table fills everywhere | M3; waiter A opens table 5, adds items, sets guests=3, taps **Pay Later** | Table 5 shows occupied with item count / total / owner=A / "بانتظار الدفع" on A's grid, B's grid, and the cashier — and the cashier's Details dialog shows the exact items | FR‑TBL‑2..3, FR‑ORD‑5, FR‑BILL‑5 | P0 |
| TBL‑08 | Lone‑waiter table state survives an app restart | M1; waiter takes table 5 (pay‑later) | Force‑kill, relaunch | Table 5 still shows occupied‑by‑me with its Edit‑Order / Cancel‑Booking buttons; the pay‑later `orderId` is intact (Edit Order opens the *same* booking, doesn't create a new one) | FR‑TBL‑4, FR‑CTL‑1, FR‑CTL‑5 | P1 |
| TBL‑09 | Late joiner converges | M3; waiter A has table 5 + table 8 occupied; bring waiter B online afterwards | On B joining | B's grid immediately shows tables 5 & 8 occupied by A (push‑on‑HELLO snapshot) without waiting for A to touch anything | FR‑CTL‑3 | P1 |
| TBL‑10 | Backend‑locked table | M2; the cashier opens table 5 from its POS (no waiter mesh involvement) | Waiter A taps table 5 | A gets the "الطاولة محجوزة / غير متاحة" dialog — can't start a second party | FR‑TBL‑6 (guard) | P1 |
| TBL‑11 | Another waiter's table is read‑only | M3; A owns table 5 | Waiter B taps table 5 | B gets the "owned by Ahmed" info dialog; no overwrite; no migrate/edit/release controls on B's card | FR‑TBL‑5..6 | P1 |
| TBL‑12 | Cashier force‑release a stuck table | M2; a table is stuck "paid‑but‑seated" or stuck occupied | Cashier: card 3‑dots → "تحرير الطاولة" → confirm | The table flips to free everywhere; the registry row is removed; `_takingOrderTables` cleared | FR‑TBL‑5 | P1 |

---

## 5. Order composition / KDS / outbox (FR‑ORD‑*)

| ID | Title | Setup | Steps | Expected | FRs | Pri |
|---|---|---|---|---|---|---|
| ORD‑01 | Compose with customisations + guests | M2, KDS up | Open a table → pick a category → tap a product with extras → ProductCustomizationDialog: choose extras, qty 2, a note → confirm; set guests=4; tap **Pay Later** | The KDS shows the order with the exact items/extras/notes, `order_type: dine_in`, note = `Table N • Waiter: X • <note>` — the **same shape** the cashier sends; a paper kitchen ticket prints (respecting the printKitchenInvoices toggle); the table goes `paymentPending`; the local cart promotes drafts→sent | FR‑ORD‑1..5 | P0 |
| ORD‑02 | Fractional quantity (half‑kilo) | M2 | Add an item with qty 0.5 → Pay Later | The KDS ticket and the on‑screen totals reflect 0.5; ⚠️ verify the **booking** on the backend isn't silently rounded to 1 (B‑11) and that closing the same cart from the *cashier* Details dialog produces the same quantity | FR‑ORD‑1, FR‑BILL‑2, B‑11 | P1 |
| ORD‑03 | KDS down ⇒ enqueued | M2; disconnect the KDS first | Open a table, add items, tap **Pay Later** | The booking is still created on the backend; the KDS order is enqueued in `waiter_outbox` (verify the entry has order_id/number/table/waiter/items/total/branch/queued_at/idempotency_key); a paper ticket still prints; the table goes `paymentPending` | FR‑ORD‑6, FR‑BILL‑3 | P0 |
| ORD‑04 | Outbox auto‑flush on KDS re‑pair | Continue ORD‑03; queue 3 orders | Reconnect the KDS | All 3 flush automatically, in queue order, no duplicates; the outbox ends empty | FR‑ORD‑7 | P0 |
| ORD‑05 | Outbox auto‑flush on connectivity return | Like ORD‑03 but the KDS is reachable and it's *internet* that drops; queue 2 orders offline | Restore internet | The 2 flush automatically | FR‑ORD‑7 | P1 |
| ORD‑06 | Outbox flush at startup | Queue an order, force‑kill the app | Relaunch (KDS up) | The queued order flushes once during boot; outbox empty | FR‑ORD‑7 | P1 |
| ORD‑07 | App killed mid‑compose ⇒ drafts restored | Open a table, add 3 items (don't send) | Force‑kill, relaunch, re‑open the same table | The 3 draft items are back in the cart with their extras/notes/qty | FR‑ORD‑2 | P1 |
| ORD‑08 | App killed mid‑flush ⇒ no duplicate sends | Queue 5 orders, KDS up; trigger the flush, then force‑kill the app after order #3 lands on the wire | Relaunch (KDS up) | Orders #4 and #5 flush; #1‑#3 do **not** re‑send (progress was persisted after each). (Acknowledged residual: a kill in the tiny window between #3 landing and its `_write` could resend #3 once — note it if it happens.) | FR‑ORD‑7 | P1 |
| ORD‑09 | Poison order dropped after 10 retries | Queue an order whose product the backend rejects (delete the meal server‑side first); KDS up | Let it cycle | After 10 failed flushes the entry is dropped; later orders behind it still flush; no infinite spin | FR‑ORD‑8 | P2 |
| ORD‑10 | Outbox empty after signout | Queue 2 orders (KDS down); End Shift | Sign back in (KDS up) | The 2 are **not** flushed (the queue was wiped); the kitchen never sees them | FR‑ORD‑9, FR‑SES‑10 | P0 |
| ORD‑11 | ⚠️ KDS connected but frozen ⇒ order must not vanish (B‑10) | M2; the KDS WS is "up" but the KDS app is hung (doesn't ACK) | Send an order | Either the order is delivered when the KDS recovers, or it's queued in the outbox after a no‑ACK timeout. *Today the waiter assumes success on "WS up" and never queues it.* | FR‑ORD‑6 | P1 |
| ORD‑12 | Two waiters' orders never interleave under one identity | M3 | A and B each send an order at the same time | The KDS sees two distinct orders, each attributed to its sender; nothing is mixed | FR‑ORD‑4 | P2 |
| ORD‑13 | Edit‑order supplemental ticket | M2; a pay‑later table owned by A | A: card → Edit Order → add an item, save | The booking is PATCHed (same booking id, not a new one); a *supplemental* kitchen ticket prints tagged `…‑EDIT` with only the new item; the local sent‑cart re‑syncs from the backend | FR‑ORD‑4, FR‑TBL‑6 | P1 |
| ORD‑14 | ⚠️ Force‑kill within 300 ms of a successful Pay Later (B‑12) | M2; open a table, add items, tap Pay Later; force‑kill the app immediately on success | Relaunch, re‑open the card → order screen → Pay Later again (no new items) | No duplicate kitchen ticket for items the original Pay Later already sent. *Today the cart drafts survived (not persisted as "sent" yet) so the re‑entry PATCHes + re‑dispatches them as an edit.* | FR‑ORD‑2, B‑12 | P2 |

---

## 6. Billing / payment / receipt (FR‑BILL‑*)

| ID | Title | Setup | Steps | Expected | FRs | Pri |
|---|---|---|---|---|---|---|
| BILL‑01 | Close cash ⇒ receipt matches the cashier byte‑for‑byte | M2; a table with items | Order screen → Create Invoice → cash → confirm tender | Booking + invoice created; the **printed customer receipt** matches a cashier‑printed receipt for the same invoice: seller block, tax number, commercial register, logo, daily order number, totals, ZATCA QR, footer; the on‑screen `_BillPreview` matches the paper; respects autoPrintCashier / second‑copy toggles; the table goes `paid` (occupied‑but‑seated) | FR‑BILL‑1..6, NFR‑CON‑3..4 | P0 |
| BILL‑02 | Tax‑inclusive math == cashier | M2 on a 15 % VAT branch; cart subtotal e.g. 33.30 | Close cash | Charged total = `round2(subtotal·1.15)` to `ApiConstants.digitsNumber`; `taxAmount = round2(subtotal·0.15)`; the backend doesn't reject‑then‑cancel a draft invoice over a rounding cent; the figures equal what the cashier produces for the identical cart | FR‑BILL‑2, NFR‑CON‑3 | P0 |
| BILL‑03 | Close with NearPay card (Android) | M4 Sunmi | Create Invoice → card → tap card on the reader | In‑app NearPay flow runs against `referenceId = bookingId`; on success the invoice is created, the table goes `paid`, the receipt prints, `transactionId` recorded | FR‑BILL‑3 | P0 |
| BILL‑04 | Close with card on iPad (remote dispatch) | M6 | Create Invoice → card | The request is forwarded to the paired display app over WS (no local SDK); success/decline propagate back | FR‑BILL‑3 | P1 |
| BILL‑05 | NearPay decline after the booking was created ⇒ retry without double‑booking | M4; force the card to decline | Create Invoice → card → declined → tap "Retry" (or dismiss & Create Invoice again, pick cash) | The retry reuses the existing `bookingId` (no second booking on the backend); on the cash retry, only one invoice is created; the cart isn't wiped | FR‑BILL‑3..4 | P0 |
| BILL‑06 | Pay‑later booking ⇒ table `paymentPending` | M2 | Order screen → Pay Later | Table goes `paymentPending` everywhere; the card offers Edit Order / Create Invoice / Cancel Booking; re‑entering the order screen shows the items as "already sent" | FR‑BILL‑5, FR‑TBL‑6 | P0 |
| BILL‑07 | Backend pay‑later with no local trace ⇒ recovered on next start | M2; create a pay‑later booking, then force‑kill the app *before* the `paymentPending` broadcast (tight window — or create the booking via the API directly with `cashier_name = <waiter name>`) | Relaunch the waiter app | The start‑time reconcile injects the orphan booking; the table reappears as `paymentPending` with its booking id; Edit Order targets that booking | FR‑BILL‑8, FR‑CTL‑5 | P1 |
| BILL‑08 | Cashier closes the table on the waiter's behalf | M2; A has a pay‑later table with items | Cashier: table card → Details dialog → Create Invoice → cash | Invoice created against the *same* booking; the cashier broadcasts `paid` (then `released` for pay‑now) so A's card flips to paid/free; A (if in the order screen for that table) is popped with a "تم الدفع" snackbar | FR‑BILL‑3, FR‑TBL‑5 | P1 |
| BILL‑09 | Send invoice via WhatsApp | M2; finish a pay‑now close (BILL‑01) | In the `_BillPreview`, tap "Send via WhatsApp" | The cashier's `SendInvoiceWhatsAppButton` flow runs against the invoice id / customer phone | FR‑BILL‑7 | P2 |
| BILL‑10 | ⚠️ Pop the order screen during `processBill` (B‑1) | M2; a table with items | Create Invoice → cash → confirm tender → during the ~1 s `processBill`, tap the AppBar back arrow | The customer must **not** end up charged with no receipt and the table stuck at `paymentPending`. Expected after the fix: either the screen is blocked for the duration, or the `paid` broadcast + receipt print fire regardless of the screen being alive. *Today: booking + invoice are created, no `paid` broadcast, no receipt, table stuck — and the cashier can double‑invoice from Details.* | FR‑BILL‑3..6, B‑1 | **P0** |
| BILL‑11 | Pay methods reflect the branch | M5 (cash‑only branch) | Open a table → Create Invoice | The tender dialog shows the branch‑enabled methods; pay‑later is always available; card methods are shown but, on confirm, fail with a clear "NearPay is not enabled for this branch" rather than charging | FR‑BILL‑1 | P1 |
| BILL‑12 | Caches cleared on signout | M2; close a card invoice (warms the NearPay/pay‑methods caches), End Shift, sign in as B on a cash‑only branch | B opens a table → Create Invoice | B does **not** see a stale card option / stale tax rate from A's branch | FR‑BILL‑1, FR‑SES‑10 | P1 |

---

## 7. Pickup / hand‑off "استلام" (FR‑PU‑*)

| ID | Title | Setup | Steps | Expected | FRs | Pri |
|---|---|---|---|---|---|---|
| PU‑01 | Cashier requests pickup ⇒ all waiters alerted, cashier silent | M3 | Cashier: a free table's card → "طلب استلام" | Both waiters get the sound + the `IncomingPickupBanner` + a feed entry; the cashier hears nothing but sees the pending card | FR‑PU‑1..2, FR‑MSG‑2 | P0 |
| PU‑02 | First waiter to accept claims it; others' banners clear | Continue PU‑01 | Waiter A taps "استلام" (on the banner or the feed row) | The cashier's card flips to "occupied by A" (a `TABLE_ASSIGN`/`assigned` is folded in); A's registry shows the table owned; waiter B's feed row flips to "A استلم الطاولة" and the accept button disappears; ⚠️ B's banner should auto‑dismiss too (B‑15 — today it lingers up to 12 s) | FR‑PU‑3, FR‑MSG‑3 | P0 |
| PU‑03 | ⚠️ Second claimer is dropped; UI doesn't revert (B‑7) | M3 with clocks **skewed by ~1 s**; cashier requests a pickup | A and B both tap "استلام" within that second | Every device converges on a single winner and never flips back to the other; the cashier's card owner matches the pickup feed's "claimed by". *Today, with skew, the device whose `claimedAt` is "earlier" wins and the other device's UI reverts; the registry owner (last `assigned` to arrive) can disagree with the feed.* | FR‑PU‑3, NFR‑CON‑2 | P1 |
| PU‑04 | Cashier cancels while pending ⇒ cleared | M3; cashier requests a pickup, no one accepts yet | Cashier: cancel the pickup | All waiters' banners/feed entries clear; the table stays whatever it was | FR‑PU‑4 | P1 |
| PU‑05 | Cashier cancels after claimed ⇒ no‑op | M3; A claims the pickup | Cashier: cancel | No‑op — the table stays "occupied by A" | FR‑PU‑4 | P1 |
| PU‑06 | Orphan‑claim recovery (cashier restart mid‑pickup) | M2; cashier requests a pickup, then force‑kill & relaunch the cashier app before A accepts; then A accepts | — | The cashier (which no longer has the original request in memory) synthesises a request record from the inbound `TABLE_PICKUP_CLAIMED` so its card still flips to "occupied by A" and the claim shows in its feed | FR‑PU‑5 | P1 |
| PU‑07 | HELLO replay of own claims | M2; A claims a pickup; then drop & restore the WS between A and the cashier | On reconnect | A re‑sends its claimed pickups to the cashier on HELLO so the cashier converges even though the original broadcast may have been missed | FR‑PU‑6 | P2 |
| PU‑08 | Composing waiter isn't interrupted by the pickup sound | M2; waiter A is in the order screen for table 7 | Cashier requests a pickup for table 3 | A hears **no** sound and sees **no** banner while in the order screen; on closing the order screen, the pickup is in A's notifications feed and can be accepted | FR‑PU‑2, FR‑CTL‑7, NFR‑USE‑3 | P1 |
| PU‑09 | Pickup with no waiters online | M2 with the waiter offline | Cashier taps "طلب استلام" | "لا يوجد نادل متصل" snackbar; no request sent | FR‑PU‑1 (guard) | P2 |
| PU‑10 | Rogue pickup from a non‑viewer ignored | M3; waiter B (or a LAN script) sends a signed `TABLE_PICKUP_REQUEST` with a non‑`viewer-` `sender_id` | — | Dropped ("from non‑viewer sender"); no tablet rings | FR‑NET‑8, FR‑PU‑1 | P1 |

---

## 8. Table migration (FR‑MIG‑*)

| ID | Title | Setup | Steps | Expected | FRs | Pri |
|---|---|---|---|---|---|---|
| MIG‑01 | Cashier migrates an occupied table | M3; A owns table 5 (pay‑later, with items + guests + booking id) | Cashier: table 5 card → migrate → pick free table 9 | The cart (drafts+sent+guests) moves to table 9; table 5 flips to free everywhere; table 9 shows occupied by A carrying the item count / total / items / **the same booking id**; the kitchen gets a "نقل طاولة 5→9" ticket | FR‑MIG‑1..3 | P0 |
| MIG‑02 | Owning waiter migrates their own table | M2; A owns table 5 | Waiter A: card → migrate → pick free table 9 | Same as MIG‑01; the backend booking is re‑pointed at table 9 first (and rolled back if the mesh guard rejects) | FR‑MIG‑1..3 | P1 |
| MIG‑03 | Non‑owner can't migrate | M3; A owns table 5 | Waiter B: there is no migrate control on B's card for table 5; if a stale callback fires, it's rejected with "لا تملك هذه الطاولة" | FR‑MIG‑1 | P1 |
| MIG‑04 | Migrate a `paymentPending` table ⇒ "Create Invoice" invoices the original booking | Continue MIG‑01 (table 9 now holds the moved pay‑later booking) | On table 9: Edit Order, then Create Invoice → cash | The invoice is created against the **original** booking id (not a new one); table 9 then closes/paid normally | FR‑MIG‑3, FR‑BILL‑3 | P1 |
| MIG‑05 | `old == new` ⇒ no‑op | — | Trigger a migrate where source == destination | Nothing changes; no broadcast | FR‑MIG‑1 | P2 |
| MIG‑06 | Non‑owner peers just observe | M3; A migrates table 5→9 | On waiter B and on the cashier | B/cashier grids reflect 5→free, 9→occupied (from the echoed release/assign) without doing the cart shuffle | FR‑MIG‑2 | P2 |

---

## 9. Shared waitlist (FR‑WL‑*)

| ID | Title | Setup | Steps | Expected | FRs | Pri |
|---|---|---|---|---|---|---|
| WL‑01 | Add/update/remove/notify/seat/cancel mirror across devices | M3 (whatsapp‑enabled branch) | On waiter A: open the waitlist sheet → add a party; edit it; notify it; seat it; (on another) cancel it | Every mutation appears on waiter B and on the cashier's waitlist within ~1 s; each is delivered as a `WAITLIST_EVENT` with a local self‑echo | FR‑WL‑1..2 | P1 |
| WL‑02 | New device gets a snapshot | M3; A has 3 waiting parties; bring B online afterwards | On B joining | B's waitlist immediately shows the 3 parties (HELLO `WAITLIST_SNAPSHOT` catch‑up) | FR‑WL‑3 | P1 |
| WL‑03 | Concurrent edits converge | M3 | A and B both edit the same party at nearly the same time | The two converge last‑write‑wins; ⚠️ verify a late joiner's snapshot can't clobber a change made in the join window (acknowledged residual) | FR‑WL‑3, NFR‑CON‑2 | P2 |
| WL‑04 | Notify a party via WhatsApp | M2 | Waitlist sheet → a party → Notify → WhatsApp | The cashier's `WhatsappService` / `WaitlistNotifyDialog` flow runs | FR‑WL‑4 | P2 |
| WL‑05 | Assign‑from‑waitlist when seating | M2; a notified party linked to a free table | Tap that table | The party is marked seated; the table opens normally | FR‑WL‑1 | P2 |

---

## 10. Notifications, calls & chat (FR‑MSG‑*)

| ID | Title | Setup | Steps | Expected | FRs | Pri |
|---|---|---|---|---|---|---|
| MSG‑01 | Cashier directed message ⇒ only that waiter alerted | M3 | Cashier: "send message" dialog → pick waiter A → send | Only A surfaces the message (and, if `isCall`, the call sound + `IncomingCallBanner`); waiter B sees nothing | FR‑MSG‑1..2 | P1 |
| MSG‑02 | Cashier broadcast "call a waiter" ⇒ all alerted | M3 | Cashier: broadcast call | Both waiters get the sound + banner + a pending feed entry with an Accept button; the cashier doesn't ring | FR‑MSG‑1..2, FR‑MSG‑4 | P1 |
| MSG‑03 | First accepter ⇒ others see "accepted by X" | Continue MSG‑02 | Waiter A taps Accept | A's feed shows "استلمت" / no Accept; waiter B's feed flips to "A تم الاستلام بواسطة" / Accept hidden; the cashier sees "accepted by A" | FR‑MSG‑3..4 | P1 |
| MSG‑04 | ⚠️ Near‑simultaneous double‑accept converges (B‑8) | M3 | A and B both tap Accept on the same broadcast before either's ACCEPTED arrives | Every device (incl. a passive third waiter and the cashier) shows the **same** accepter. *Today A shows "by A", B shows "by B", third parties show whichever arrived first.* | FR‑MSG‑3 | P2 |
| MSG‑05 | Waiter→waiter call blocked | M3 | (Via a dev hook that re‑enables `CallWaiterDialog` on a waiter, or directly) attempt `controller.sendMessage(isCall: true)` from a waiter session | Rejected with a `StateError`; nothing broadcast | FR‑MSG‑1 | P2 |
| MSG‑06 | Unread badge + mark‑read on tab switch | M2 | Cashier sends 2 messages while the waiter is on the Tables tab; then the waiter switches to the Notifications tab | The bell badge shows 2, then clears the moment the Notifications tab is selected (mark‑read owned by `WaiterHomeScreen`, not by the screen's `initState`) | FR‑MSG‑4 | P1 |
| MSG‑07 | Composing waiter — call handling | M2; waiter A in the order screen | Cashier broadcasts a call | Per spec the call **sound** should be suppressed while composing (⚠️ B‑9 — today it plays); the message still lands in the feed and the badge updates; on closing the order screen the banner can be acted on | FR‑MSG‑2, FR‑CTL‑7 | P2 |

---

## 11. Config sync — cashier → waiter (FR‑CFG‑*)

| ID | Title | Setup | Steps | Expected | FRs | Pri |
|---|---|---|---|---|---|---|
| CFG‑01 | Waiter joins ⇒ cashier pushes printer list + KDS endpoint on HELLO | M2; the cashier has a kitchen printer configured and is connected to a KDS | Bring the waiter online | The waiter's `WaiterConfigStore` receives `CONFIG_KITCHEN_PRINTERS` + `CONFIG_KDS_ENDPOINT`, persists them, and (for the KDS endpoint) reconnects `DisplayAppService` if it's pointed elsewhere | FR‑CFG‑1..3 | P1 |
| CFG‑02 | Cashier changes a kitchen printer ⇒ pushed to all waiters | M3 | Cashier: edit a kitchen printer in the printers settings | Both waiters' config stores get the new (higher‑version) snapshot | FR‑CFG‑1..2 | P1 |
| CFG‑03 | Repeated pushes are idempotent | M2 | Cashier re‑saves the same printer config 3× | The waiter's store version‑gates — no churn, no duplicate apply | FR‑CFG‑2 | P2 |
| CFG‑04 | Cold‑start waiter has config before the first NEW_ORDER | M2; cashier pushed config last session | Force‑kill & relaunch the waiter; immediately send an order | The persisted KDS endpoint is re‑applied during boot (before the mesh comes up), so the order goes to the right KDS | FR‑CFG‑2..3 | P1 |
| CFG‑05 | Signed‑in resume re‑applies the KDS endpoint | M2; the cashier moved the KDS to a new host last session | Relaunch the waiter | `DisplayAppService` reconnects to the stored host:port on resume | FR‑CFG‑3 | P1 |
| CFG‑06 | ⚠️ Config from a non‑viewer ignored (B‑2) | M3; waiter B sends a valid‑MAC `CONFIG_KITCHEN_PRINTERS` / `CONFIG_KDS_ENDPOINT` with a non‑`viewer-` `sender_id` | — | Waiter A ignores it. *Today A applies it.* | FR‑CFG‑1, FR‑NET‑8 | P1 |

---

## 12. Per‑device printer settings (FR‑PRN‑*)

| ID | Title | Setup | Steps | Expected | FRs | Pri |
|---|---|---|---|---|---|---|
| PRN‑01 | Printer hub reachable, two tabs | M1 | Profile → "إعدادات الأجهزة والطباعة" | Two tabs: "الإعدادات" (printer list via the shared `PrintersTabView`) and "اللغة" | FR‑PRN‑1 | P1 |
| PRN‑02 | Add / edit / test / remove a printer (shared UI) | M1 | In the printers tab: add a WiFi printer (IP, port, paper width, role, copies), test print, edit it, remove it | Uses the cashier's add/edit dialogs and the same device/category/kitchen‑route registries — no forked UI; the change persists | FR‑PRN‑1..2 | P1 |
| PRN‑03 | Invoice language tab drives the receipt | M1 | Language tab → set primary = en, secondary = ar, allow secondary = on; then close a pay‑now invoice | The printed receipt (and the `_BillPreview`) render bilingual en/ar per the setting | FR‑PRN‑1 | P1 |

---

## 13. Resilience / failure injection (NFR‑REL‑*, NFR‑PERF‑*)

| ID | Title | Setup | Steps | Expected | FRs | Pri |
|---|---|---|---|---|---|---|
| RES‑01 | Wi‑Fi drops 30 s mid‑shift, then recovers | M3, mid‑service | Pull Wi‑Fi on waiter A for 30 s, restore | A re‑pairs with the cashier and waiter B (reconnect loop); no table/cart/draft data lost; no duplicate kitchen tickets; A's offline‑then‑online flicker resolves (⚠️ B‑14 if A stays "offline" on peers) | NFR‑REL‑5, FR‑NET‑3 | P1 |
| RES‑02 | Backend 401 to a waiter | M2; configure the backend to 401 a waiter on `getBookings` | Cold start the waiter | The start‑time reconcile's `getBookings(skipGlobalAuth: true)` swallows the 401 — the session is **not** torn down; the rest of boot proceeds | NFR‑SEC‑6, FR‑CTL‑5 | P1 |
| RES‑03 | Partial `start()` failure | M2; make the WS server bind fail (hold every candidate port) | Cold start | `start()` releases whatever it brought up, doesn't wedge `_running=true`; a later retry can succeed; the grid still loads from `getTables()` | NFR‑REL‑1, FR‑CTL‑1 | P2 |
| RES‑04 | `stop()` during an in‑flight `start()` | M2; trigger `ensureViewer`/`start` twice in quick succession (e.g. the cashier's tables screen rebuilds during login) | — | Only one mesh comes up (no `…viewer (2)` service); if a `stop()` lands mid‑`start()`, the controller unwinds and stays stopped | FR‑CTL‑1..2 | P2 |
| RES‑05 | Force‑kill at each critical point | M2 | Force‑kill the waiter app at: (a) mid‑compose, (b) mid‑Pay‑Later, (c) mid‑outbox‑flush, (d) mid‑bill (`processBill`), (e) mid‑`dispose()` of the order screen, (f) mid‑persist (during a registry/cart flush). Relaunch each time | (a) drafts restored; (b) booking either created+visible via reconcile or not at all — never a half state; (c) no duplicate sends; (d) ⚠️ B‑1 — should be recoverable; (e) ⚠️ A‑1..A‑7 — table not stuck; (f) ⚠️ B‑5 — wiped state doesn't resurrect, dual‑slot recovers a corrupt write | NFR‑REL‑4, A‑*, B‑1, B‑5, B‑12 | P1 |
| RES‑06 | KDS socket down for the whole shift | M2; never connect a KDS | Take 3 tables to pay‑later | All 3 bookings created on the backend; 3 orders queued in the outbox; paper tickets print; bring the KDS up at end of shift → all flush once, in order | FR‑ORD‑6..7, NFR‑REL‑3 | P1 |
| RES‑07 | Profile / branch‑receipt prefetch fails | M2; block `/seller/branches` | Cold start, then close a pay‑now invoice | Boot continues (warning logged); the receipt still renders from `getInvoice` (header may be sparser but the print doesn't fail) | NFR‑REL‑3, FR‑BILL‑6 | P2 |
| RES‑08 | Clock skew between devices | M3 with tablets' clocks off by ~30 s | Run PU‑03 and MSG‑04 | Pickup‑claim and call‑accept winners are consistent across devices (⚠️ B‑7, B‑8) | NFR‑CON‑2, FR‑PU‑3, FR‑MSG‑3 | P2 |

---

## 14. Quick smoke (P0 only) — run on every build

SES‑01, SES‑07, SES‑10, SES‑11 · DISC‑01, DISC‑02 · NET‑02 · TBL‑02, **TBL‑03**,
**TBL‑04** · ORD‑01, ORD‑03, ORD‑04, ORD‑10 · BILL‑01, BILL‑02, BILL‑03, BILL‑05,
BILL‑06, **BILL‑10** · PU‑01, PU‑02 · MIG‑01.

The bolded ones are the regression tests for the reported "stuck جاري اخذ الطلب" bug
(TBL‑03/04) and the "charged with no receipt" bug (BILL‑10) — they must be re‑run and
must pass after any fix in that area.
