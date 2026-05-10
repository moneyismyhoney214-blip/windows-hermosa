import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../locator.dart';
import 'api/country_code_service.dart';
import 'api/order_service.dart';
import 'invoice_html_pdf_service.dart';
import 'whatsapp_service.dart';

/// Reasons a dispatch attempt may not produce a network call.
enum WhatsAppDispatchOutcome {
  /// Sent successfully — WAWP accepted the payload.
  success,

  /// Already in progress for this invoiceId — caller MUST not retry; the
  /// in-flight request will surface its own result via the original future.
  alreadyInFlight,

  /// Already sent successfully earlier in this app session for this invoiceId.
  /// The button surfaces this as "Sent ✓" and only allows resend after an
  /// explicit confirmation.
  alreadySent,

  /// No customer is attached to the invoice, or their phone is empty.
  noCustomerPhone,

  /// WAWP credentials are not configured on this branch — backend
  /// `/seller/branches/{id}/settings.whatsapp.{instance_id, instance_token}`
  /// is missing or empty, so we have no way to talk to WAWP.
  credentialsMissing,

  /// Local PDF generation failed — `InvoiceHtmlPdfService` couldn't
  /// produce a non-empty file (HTML→PDF plugin failure, disk full, etc.).
  pdfUrlUnavailable,

  /// WAWP (or the deep-link fallback) failed.
  failure,
}

@immutable
class WhatsAppDispatchResult {
  final WhatsAppDispatchOutcome outcome;
  final String? errorMessage;

  const WhatsAppDispatchResult._(this.outcome, [this.errorMessage]);

  const WhatsAppDispatchResult.success() : this._(WhatsAppDispatchOutcome.success);
  const WhatsAppDispatchResult.alreadyInFlight() : this._(WhatsAppDispatchOutcome.alreadyInFlight);
  const WhatsAppDispatchResult.alreadySent() : this._(WhatsAppDispatchOutcome.alreadySent);
  const WhatsAppDispatchResult.noCustomerPhone() : this._(WhatsAppDispatchOutcome.noCustomerPhone);
  const WhatsAppDispatchResult.credentialsMissing() : this._(WhatsAppDispatchOutcome.credentialsMissing);
  const WhatsAppDispatchResult.pdfUrlUnavailable() : this._(WhatsAppDispatchOutcome.pdfUrlUnavailable);
  const WhatsAppDispatchResult.failure(String message) : this._(WhatsAppDispatchOutcome.failure, message);

  bool get ok => outcome == WhatsAppDispatchOutcome.success;
}

/// Sends invoice PDFs over WhatsApp by talking to WAWP **directly from
/// the app**, the same way the waiter waitlist does. This bypasses the
/// backend's `/seller/invoices/send-whatsapp` flow because that one is
/// gated by the `whatsapp_status` branch toggle, while WAWP creds
/// (`whatsapp.instance_id` + `whatsapp.instance_token`) are seeded into
/// memory regardless of that toggle by `BranchService`.
///
/// Flow per call:
///   1. Pre-flight: branch toggle, customer phone, in-flight + sent
///      guards (in that order).
///   2. Render the PDF locally via `InvoiceHtmlPdfService` — the same
///      pipeline the print preview already uses. Read the file bytes
///      so we don't depend on a public URL anywhere (the backend's
///      `/seller/branches/{id}/invoices/{id}/pdf` route was 500-ing on
///      a Laravel storage permission issue, and there is no public
///      upload endpoint we could host on).
///   3. Hand the bytes + caption to `WhatsAppService.sendInvoicePdf`,
///      which base64-encodes them inline and calls
///      `https://api.wawp.net/v2/send/pdf`. Falls back to a `wa.me`
///      deep link with the caption only if the API leg fails.
///
/// THIS IS A CREDIT-SENSITIVE FEATURE: every successful WAWP call burns
/// a credit on the merchant's balance. The dispatcher therefore runs
/// three duplicate guards in series:
///
///   1. **In-flight lock** (`_inFlight`) — the same invoiceId cannot have
///      two concurrent requests. A second call while one is pending
///      returns [WhatsAppDispatchOutcome.alreadyInFlight] without
///      touching the network.
///
///   2. **Sent set** (`_sent`) — once a request returns ok, the invoiceId
///      is remembered for the lifetime of the app process. Subsequent
///      calls return [WhatsAppDispatchOutcome.alreadySent] unless the
///      caller passes `force: true` (used after a confirm-resend dialog).
///
///   3. **Pre-flight validation** — branch toggle off or empty phone
///      short circuits before any guard or network work.
///
/// `notifyListeners` is fired when state changes so UIs can repaint
/// "Sent ✓" / "Sending…" without owning the state themselves.
class InvoiceWhatsAppDispatcher extends ChangeNotifier {
  final Set<String> _inFlight = <String>{};
  final Set<String> _sent = <String>{};

  bool isInFlight(String invoiceId) => _inFlight.contains(invoiceId);
  bool isSent(String invoiceId) => _sent.contains(invoiceId);

  /// Send the invoice PDF on WhatsApp.
  ///
  /// Pass `force: true` only after the user explicitly confirmed a resend
  /// (e.g. through a confirmation dialog). Passing `force: true` bypasses
  /// the [_sent] guard but never bypasses the [_inFlight] guard.
  Future<WhatsAppDispatchResult> sendInvoice({
    required String invoiceId,
    required String? customerPhone,
    String? customerName,
    String? invoiceNumber,
    bool force = false,
  }) async {
    debugPrint('🧾 [WA-Invoice] sendInvoice start invoiceId=$invoiceId '
        'phoneFromCaller="${customerPhone ?? ''}" name="${customerName ?? ''}"');

    if (_inFlight.contains(invoiceId)) {
      debugPrint('🧾 [WA-Invoice] alreadyInFlight invoiceId=$invoiceId');
      return const WhatsAppDispatchResult.alreadyInFlight();
    }
    if (!force && _sent.contains(invoiceId)) {
      debugPrint('🧾 [WA-Invoice] alreadySent invoiceId=$invoiceId');
      return const WhatsAppDispatchResult.alreadySent();
    }

    _inFlight.add(invoiceId);
    notifyListeners();
    try {
      await whatsAppService.initialize();
      if (!whatsAppService.config.isApiReady) {
        debugPrint('🧾 [WA-Invoice] credentialsMissing — '
            'instanceId="${whatsAppService.config.instanceId ?? ''}" '
            'tokenLen=${whatsAppService.config.accessToken?.length ?? 0}');
        return const WhatsAppDispatchResult.credentialsMissing();
      }

      // Resolve customer phone — list rows often only carry a name, so
      // fall back to a `getInvoice(invoiceId)` lookup that returns the
      // full booking + customer record. This mirrors how the print
      // preview already loads invoice details on demand.
      var phone = customerPhone?.trim() ?? '';
      var resolvedName = customerName?.trim();
      if (phone.isEmpty) {
        debugPrint('🧾 [WA-Invoice] caller-supplied phone empty — '
            'fetching invoice details for $invoiceId');
        final fetched = await _fetchCustomerFromBackend(invoiceId);
        if (fetched != null) {
          phone = fetched.phone ?? '';
          resolvedName = (resolvedName != null && resolvedName.isNotEmpty)
              ? resolvedName
              : fetched.name;
          debugPrint('🧾 [WA-Invoice] backend resolved '
              'phone="${fetched.phone ?? ''}" name="${fetched.name ?? ''}"');
        } else {
          debugPrint('🧾 [WA-Invoice] backend lookup failed/empty for $invoiceId');
        }
      }
      if (phone.isEmpty) {
        debugPrint('🧾 [WA-Invoice] noCustomerPhone after fallback — bailing');
        return const WhatsAppDispatchResult.noCustomerPhone();
      }

      final pdfBytes = await _renderPdfBytes(invoiceId);
      if (pdfBytes == null || pdfBytes.isEmpty) {
        debugPrint('🧾 [WA-Invoice] PDF render failed for $invoiceId');
        return const WhatsAppDispatchResult.pdfUrlUnavailable();
      }
      debugPrint('🧾 [WA-Invoice] PDF rendered ${pdfBytes.length} bytes');

      final caption = _renderCaption(
        customerName: resolvedName,
        invoiceNumber: invoiceNumber,
      );
      final filename = _renderFilename(invoiceNumber: invoiceNumber);
      final countryCode = await _resolveBranchCountryCode();
      debugPrint('🧾 [WA-Invoice] sending via WAWP '
          'phone="$phone" countryCode="${countryCode ?? '(default)'}" '
          'filename="$filename"');

      final result = await whatsAppService.sendInvoicePdf(
        rawPhone: phone,
        pdfBytes: pdfBytes,
        caption: caption,
        filename: filename,
        countryCodeOverride: countryCode,
      );
      if (result.ok) {
        _sent.add(invoiceId);
        debugPrint('🧾 [WA-Invoice] success channel=${result.deliveredVia}');
        return const WhatsAppDispatchResult.success();
      }
      debugPrint('🧾 [WA-Invoice] WAWP failure: ${result.errorMessage}');
      return WhatsAppDispatchResult.failure(
        result.errorMessage ?? 'wawp_unknown_error',
      );
    } catch (e, st) {
      debugPrint('🧾 [WA-Invoice] dispatcher threw: $e\n$st');
      return WhatsAppDispatchResult.failure(e.toString());
    } finally {
      _inFlight.remove(invoiceId);
      notifyListeners();
    }
  }

  /// Pull the customer phone (and name when available) out of the
  /// detailed `getInvoice` response. The list endpoint trims customer
  /// info to keep the page lightweight, so when the row's row data is
  /// missing a phone we resolve it on demand here.
  ///
  /// Backend bug workaround: `/seller/branches/{branch}/invoices/{id}`
  /// can return `client.mobile=""` and `client.name="عميل عام"` even
  /// when the underlying booking has a real customer attached. The
  /// booking endpoint (`/seller/branches/{branch}/bookings/{id}`)
  /// returns `data.user.mobile` correctly for the same row, so we
  /// re-resolve from there when the invoice payload looks empty.
  Future<_FetchedCustomer?> _fetchCustomerFromBackend(String invoiceId) async {
    try {
      final response = await getIt<OrderService>().getInvoice(invoiceId);
      final payload = _asMap(response['data']) ?? response;
      final invoice = _asMap(payload['invoice']) ?? payload;
      final booking = _asMap(payload['booking']) ?? _asMap(invoice['booking']);
      final customer = _asMap(invoice['customer']) ??
          _asMap(payload['customer']) ??
          _asMap(booking?['customer']) ??
          _asMap(invoice['client']) ??
          _asMap(payload['client']);

      var phone = _pick([
        invoice['customer_phone'],
        invoice['client_phone'],
        invoice['phone'],
        payload['customer_phone'],
        payload['client_phone'],
        customer?['mobile'],
        customer?['phone'],
        customer?['phone_number'],
        booking?['customer_phone'],
      ]);
      var name = _pick([
        invoice['customer_name'],
        invoice['client_name'],
        payload['customer_name'],
        customer?['name'],
        booking?['customer_name'],
      ]);

      if (phone == null || phone.isEmpty) {
        final bookingId = _pick([
          payload['booking_id'],
          invoice['booking_id'],
          booking?['id'],
        ]);
        if (bookingId != null && bookingId.isNotEmpty) {
          final fromBooking = await _fetchCustomerFromBooking(bookingId);
          if (fromBooking != null) {
            if (phone == null || phone.isEmpty) {
              phone = fromBooking.phone;
            }
            if (name == null || name.isEmpty || name == 'عميل عام') {
              name = fromBooking.name ?? name;
            }
          }
        }
      }

      if (phone == null && name == null) return null;
      return _FetchedCustomer(phone: phone, name: name);
    } catch (e) {
      debugPrint('🧾 [WA-Invoice] _fetchCustomerFromBackend threw: $e');
      return null;
    }
  }

  /// Pull customer phone/name from `/seller/branches/{branch}/bookings/{id}`,
  /// which exposes the linked customer under `data.user.{name,mobile}`.
  /// Used as a second-stage fallback when the invoice serializer
  /// drops the customer (returns `عميل عام` + empty mobile).
  Future<_FetchedCustomer?> _fetchCustomerFromBooking(String bookingId) async {
    try {
      final response = await getIt<OrderService>().getBookingDetails(bookingId);
      final payload = _asMap(response['data']) ?? response;
      final user = _asMap(payload['user']) ??
          _asMap(payload['customer']) ??
          _asMap(payload['userable']) ??
          _asMap(payload['client']);
      if (user == null) return null;

      final phone = _pick([
        user['mobile'],
        user['mobile_display'],
        user['phone'],
        user['phone_number'],
      ]);
      final name = _pick([user['name'], user['fullname']]);
      debugPrint('🧾 [WA-Invoice] booking fallback resolved '
          'bookingId=$bookingId phone="${phone ?? ''}" name="${name ?? ''}"');
      if (phone == null && name == null) return null;
      return _FetchedCustomer(phone: phone, name: name);
    } catch (e) {
      debugPrint('🧾 [WA-Invoice] _fetchCustomerFromBooking threw: $e');
      return null;
    }
  }

  static String? _pick(List<dynamic> candidates) {
    for (final c in candidates) {
      final t = c?.toString().trim();
      if (t != null && t.isNotEmpty && t.toLowerCase() != 'null') {
        return t;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return null;
  }

  /// Resolve the area code (e.g. `+20`, `+966`) of the branch's country
  /// so [WhatsAppService.normalizePhone] doesn't fall back to its hard-coded
  /// `+966` default for branches outside Saudi. Returns null when the
  /// list isn't available — the WhatsApp service then keeps its current
  /// default, which is still better than a hard failure.
  Future<String?> _resolveBranchCountryCode() async {
    try {
      // Fast path: the list is already cached in memory.
      if (countryCodeService.options.isNotEmpty) {
        return countryCodeService.defaultForBranch().areaCode;
      }
      await countryCodeService.load();
      return countryCodeService.defaultForBranch().areaCode;
    } catch (_) {
      return null;
    }
  }

  /// Render the invoice PDF locally via [InvoiceHtmlPdfService] (the same
  /// pipeline the print preview screen uses) and return the raw bytes
  /// so [WhatsAppService.sendInvoicePdf] can inline them as base64.
  ///
  /// `generatePdfFromInvoice` silently falls back to writing raw HTML when
  /// the `flutter_html_to_pdf_plus` plugin throws — that path is fine for
  /// the print preview but would surface on WhatsApp as a "broken PDF"
  /// because we'd inline HTML bytes labelled as `application/pdf`. Guard
  /// against that by validating the PDF magic header (`%PDF-`) and bailing
  /// when it's missing, so the dispatcher returns `pdfUrlUnavailable`
  /// instead of shipping garbage to WAWP.
  Future<Uint8List?> _renderPdfBytes(String invoiceId) async {
    try {
      final pdfService = getIt<InvoiceHtmlPdfService>();
      final path = await pdfService.generatePdfFromInvoice(invoiceId);
      if (path.isEmpty) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      // Best-effort cleanup of the temp file — failures here are
      // harmless, the OS reaps the temp dir anyway.
      unawaited(file.delete().catchError((_) => file));
      if (!_looksLikePdf(bytes)) {
        debugPrint('🧾 [WA-Invoice] generated file is not a PDF — '
            'path="$path" firstBytes="${_describeFirstBytes(bytes)}". '
            'Likely the html→pdf plugin hit a fallback. Bailing instead '
            'of sending corrupt bytes.');
        return null;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Real PDFs always start with the ASCII magic `%PDF-` (5 bytes).
  /// Anything else (HTML fallback, empty file, etc.) means the upstream
  /// generator silently produced something WhatsApp can't render.
  static bool _looksLikePdf(Uint8List bytes) {
    if (bytes.length < 5) return false;
    return bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46 && // F
        bytes[4] == 0x2D; // -
  }

  static String _describeFirstBytes(Uint8List bytes) {
    if (bytes.isEmpty) return '(empty)';
    final preview = bytes.length > 16 ? bytes.sublist(0, 16) : bytes;
    final ascii = preview
        .map((b) => (b >= 0x20 && b < 0x7F) ? String.fromCharCode(b) : '.')
        .join();
    return '"$ascii" (${bytes.length} bytes total)';
  }

  String _renderCaption({String? customerName, String? invoiceNumber}) {
    final number = invoiceNumber?.trim();
    final name = customerName?.trim();
    if (number != null && number.isNotEmpty && name != null && name.isNotEmpty) {
      return 'مرحباً $name، فاتورتك رقم $number 🧾';
    }
    if (number != null && number.isNotEmpty) {
      return 'فاتورتك رقم $number 🧾';
    }
    if (name != null && name.isNotEmpty) {
      return 'مرحباً $name، إليك نسخة فاتورتك 🧾';
    }
    return 'إليك نسخة فاتورتك 🧾';
  }

  String _renderFilename({String? invoiceNumber}) {
    final number = invoiceNumber?.trim();
    if (number == null || number.isEmpty) return 'invoice.pdf';
    final safe = number.replaceAll(RegExp(r'[^A-Za-z0-9\-_]'), '_');
    return 'invoice_$safe.pdf';
  }

  @visibleForTesting
  void resetForTests() {
    _inFlight.clear();
    _sent.clear();
  }
}

final invoiceWhatsAppDispatcher = InvoiceWhatsAppDispatcher();

class _FetchedCustomer {
  final String? phone;
  final String? name;
  const _FetchedCustomer({this.phone, this.name});
}
