# App Review Notes — Hermosa POS

Paste this content (translated as needed) into App Store Connect →
"App Review Information" → "Notes" before submitting.

---

## What Hermosa is

Hermosa is a B2B point-of-sale (POS) iPad application used by salons,
restaurants, and small retail businesses in Saudi Arabia and the Gulf
region. Cashiers and waiters log in with credentials issued by their
employer (the merchant); the app does not support self-service
account creation. New merchants register via the Hermosa sales team
at https://hermosaapp.com.

The app is iPad-only and landscape-only because it is designed to
replace a traditional cash register on a stand at a counter.

---

## Demo account for App Review

```
Email:    review@hermosaapp.com
Password: AppleReview2026!
Branch:   Riyadh - Hermosa Demo
```

The account is pre-loaded with sample products, customers, and
invoices so the reviewer can exercise the full flow:

1. Browse the product catalog.
2. Add items to the cart.
3. Optionally select a customer.
4. Tap **Pay** → choose a payment method:
   - **Cash** — fully functional inside the app.
   - **Bank transfer** — fully functional inside the app.
   - **Card (NearPay)** — see the "Hardware-Specific Content" note
     below. On iPad, this requires an external Sunmi POS terminal
     connected over the local network. The reviewer can preview the
     UI but the actual card swipe will return "no terminal connected"
     since the hardware is not attached.
5. The invoice is generated and can be printed (Wi-Fi printer) or
   shared as a PDF.

---

## Hardware-Specific Content (Apple Guideline 3.1.4)

The "Card" payment option uses **NearPay**, a Saudi-licensed card
acquirer whose SDK runs on **certified Sunmi/Centerm Android POS
hardware**. iPads do not have Tap-to-Pay-on-iPhone equivalents in
Saudi Arabia today, so the iPad cashier does **not** read cards
directly. Instead:

```
iPad (Hermosa cashier)        Sunmi POS terminal (separate device)
       │                                  │
       │  START_PAYMENT  (WebSocket)      │
       │  ───────────────────────────────►│
       │                                  │   NearPay reads card
       │                                  │   (NFC/EMV chip)
       │  PAYMENT_SUCCESS                 │
       │ ◄──────────────────────────────  │
```

This pattern is permitted under **Guideline 3.1.4 (Hardware-Specific
Content)**: the iPad app provides extra functionality only when
synced with the certified payment terminal. Card transactions are
processed entirely on the merchant-owned hardware and the bank's
infrastructure; no funds flow through Apple or the iPad.

For App Store reviewers without access to a Sunmi terminal, the
iPad app continues to function fully for cash payments, bank
transfers, cart management, customer management, invoicing, and
printing.

---

## Privacy

- **Privacy policy:** https://hermosaapp.com/pages/privacy-policy
  (also accessible inside the app via Settings → Profile → Legal)
- **Terms and conditions:** https://hermosaapp.com/pages/terms-conditions
  (also accessible inside the app via Settings → Profile → Legal)
- **Privacy manifest:** included as `Runner/PrivacyInfo.xcprivacy`.
- **No tracking, no IDFA, no third-party advertising or analytics.**
- All collected data (customer name/phone/email/payment) stays inside
  the merchant's Hermosa tenant and is never shared with third parties.

---

## Permissions and why they exist

| Permission | Why |
|---|---|
| Camera | QR code scanning for product / invoice lookup |
| Bluetooth | Listed for cross-platform compatibility; iPad UI does NOT expose Bluetooth printing — only Wi-Fi printers are selectable on iPad |
| Local Network | Discover Wi-Fi receipt printers and the Sunmi card terminal on the merchant's local network |
| NFC | Compatibility check for NearPay (returns "unsupported" on iPad and the SDK is then bypassed) |
| Photo Library | Save invoice/receipt PDFs to the iPad photo library on demand |
| Microphone | Listed for plugin compatibility; not actively used |

---

## Things the reviewer should know

- The app is in **Arabic (default) and English**. The reviewer can
  switch via the language icon at the top right of the login screen.
- The app is **landscape-only** by design (POS form factor).
- The app is **iPad-only** (`TARGETED_DEVICE_FAMILY = "2"`).
- **No in-app purchases.** Subscription billing happens out-of-band
  between Hermosa and the merchant; this is a B2B SAAS product.
- **No user-generated content / no chat.** Cashiers can only see
  data scoped to their own merchant tenant.
- **No login required to view privacy policy / terms** — these are
  accessible from the login screen footer.

---

## Known visual elements that look unusual but are correct

- The cart panel and product grid scale to the iPad form factor.
  On a 12.9" iPad in landscape they fill the screen edge-to-edge.
- The "Customer Display" tab in Settings is hidden on iPad because
  the underlying Sunmi-only feature is Android exclusive.
- The "Bluetooth" connection-type chip in Printer Settings is hidden
  on iPad for the same reason. iPad merchants use Wi-Fi printers.

---

## Build info

- Bundle ID: `com.hermosa.hermosaapp`
- Version: matches `pubspec.yaml` `version` field
- Min iOS: 13.0
- Targeted device: iPad only
- Orientation: landscape only
- Privacy manifest: bundled
- Encryption export compliance: standard TLS only — exempt under
  §740.17(b)(1); declared via `ITSAppUsesNonExemptEncryption=false`.

---

## Contact

Engineering & app review questions: support@hermosaapp.com
