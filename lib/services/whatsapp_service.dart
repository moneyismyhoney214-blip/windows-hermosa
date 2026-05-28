import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Result of a send attempt. Kept compact on purpose — the UI just
/// needs to know "did a message reach the customer" plus a
/// human-readable reason when it didn't.
class WhatsAppSendResult {
  /// True when the WAWP API accepted the payload. Every send goes through
  /// the WAWP HTTP API — there is no `wa.me` deep-link fallback anywhere
  /// in this service, so an `ok` result always means WAWP responded 2xx.
  final bool ok;

  /// What actually happened — useful for the snackbar copy and for
  /// telemetry when we add it.
  final WhatsAppSendChannel deliveredVia;

  /// Non-null only when [ok] is false; a short user-facing message
  /// (already localized by the service).
  final String? errorMessage;

  const WhatsAppSendResult._(this.ok, this.deliveredVia, this.errorMessage);

  const WhatsAppSendResult.apiOk()
      : this._(true, WhatsAppSendChannel.wawpApi, null);
  const WhatsAppSendResult.failure(String reason)
      : this._(false, WhatsAppSendChannel.none, reason);
}

enum WhatsAppSendChannel { wawpApi, none }

/// Host-configurable WAWP credentials.
///
/// [instanceId] + [accessToken] are the two tokens you copy from the
/// WAWP dashboard (API tab). [defaultCountryCode] is the phone prefix
/// we auto-apply when the host types a number without one (e.g. "0501…"
/// → "+966501…"). [messageTemplate] accepts `{name}` and `{table}`
/// placeholders — plaintext only, since WhatsApp doesn't support HTML
/// in chat messages.
@immutable
class WhatsAppConfig {
  final String? instanceId;
  final String? accessToken;
  final String defaultCountryCode;
  final String messageTemplate;

  const WhatsAppConfig({
    this.instanceId,
    this.accessToken,
    this.defaultCountryCode = '+966',
    this.messageTemplate = _defaultTemplate,
  });

  static const String _defaultTemplate =
      'مرحباً {name}، طاولتك رقم {table} أصبحت جاهزة الآن. نتشرف باستقبالك.';

  /// True when we have enough to call the WAWP API.
  bool get isApiReady =>
      (instanceId ?? '').trim().isNotEmpty &&
      (accessToken ?? '').trim().isNotEmpty;

  WhatsAppConfig copyWith({
    String? instanceId,
    String? accessToken,
    String? defaultCountryCode,
    String? messageTemplate,
  }) {
    return WhatsAppConfig(
      instanceId: instanceId ?? this.instanceId,
      accessToken: accessToken ?? this.accessToken,
      defaultCountryCode: defaultCountryCode ?? this.defaultCountryCode,
      messageTemplate: messageTemplate ?? this.messageTemplate,
    );
  }

  // WAWP creds are backend-sourced and in-memory only — NOT persisted here.
  Map<String, dynamic> toJson() => {
        'defaultCountryCode': defaultCountryCode,
        'messageTemplate': messageTemplate,
      };

  factory WhatsAppConfig.fromJson(Map<String, dynamic> json) => WhatsAppConfig(
        defaultCountryCode:
            (json['defaultCountryCode'] as String?)?.trim().isNotEmpty == true
                ? (json['defaultCountryCode'] as String).trim()
                : '+966',
        messageTemplate:
            (json['messageTemplate'] as String?)?.trim().isNotEmpty == true
                ? json['messageTemplate'] as String
                : _defaultTemplate,
      );
}

/// Singleton gateway for sending WhatsApp messages.
///
/// Both [sendTableReady] and [sendInvoicePdf] are **WAWP HTTP API only**
/// — there is no `wa.me` deep-link fallback. If the branch has no WAWP
/// credentials, or the API call fails/times out, the method returns a
/// failure result and the caller shows a "something went wrong — contact
/// support" message. Opening `wa.me` was banned because the deep link
/// silently mangles a wrong phone (e.g. an extra leading zero gets
/// "fixed" into a doubled country code) and sends the host to a chat
/// with the wrong customer.
class WhatsAppService extends ChangeNotifier {
  static final WhatsAppService _instance = WhatsAppService._internal();
  factory WhatsAppService() => _instance;
  WhatsAppService._internal();

  static const String _storageKey = 'whatsapp_wawp_config_v1';
  static const String _apiEndpoint = 'https://api.wawp.net/v2/send/text';
  static const String _pdfEndpoint = 'https://api.wawp.net/v2/send/pdf';
  static const Duration _apiTimeout = Duration(seconds: 25);
  static const Duration _mediaTimeout = Duration(seconds: 30);

  WhatsAppConfig _config = const WhatsAppConfig();
  WhatsAppConfig get config => _config;

  bool _initialized = false;
  Future<void>? _initFuture;

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final stored = WhatsAppConfig.fromJson(decoded);
          // Preserve in-memory creds seeded from backend while prefs were loading.
          _config = stored.copyWith(
            instanceId: _config.instanceId,
            accessToken: _config.accessToken,
          );
        }
      }
    } catch (e, st) {
      developer.log(
        'WhatsAppService: failed to load config — using defaults',
        error: e,
        stackTrace: st,
      );
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> updateConfig(WhatsAppConfig next) async {
    _config = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(next.toJson()));
    } catch (e, st) {
      developer.log(
        'WhatsAppService: failed to persist config',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Seed WAWP credentials from the backend `/seller/branches/{id}/settings`
  /// payload. Treats `instanceId` + `accessToken` as a single unit:
  /// both must be non-empty for the seed to take effect. Partial input
  /// is rejected so we never end up with a new id paired against a
  /// stale token from a previous branch.
  ///
  /// User-tuned fields (`defaultCountryCode`, `messageTemplate`) are
  /// preserved. Not persisted to SharedPreferences — backend is
  /// re-fetched on each session, so the in-memory copy is enough.
  ///
  /// Backend uses the field name `instance_token`; WAWP API expects
  /// `access_token`. We keep the API contract and translate at the edge.
  void applyBackendCredentials({String? instanceId, String? accessToken}) {
    final id = instanceId?.trim() ?? '';
    final tok = accessToken?.trim() ?? '';
    if (id.isEmpty || tok.isEmpty) return;

    if (id == (_config.instanceId ?? '') &&
        tok == (_config.accessToken ?? '')) {
      return;
    }
    _config = _config.copyWith(instanceId: id, accessToken: tok);
    // Don't touch _initialized — owned by _load; toggling here would lose prefs.
    notifyListeners();
  }

  /// Drop any in-memory WAWP credentials. Used when the active branch
  /// changes to one that has no WhatsApp configuration — without this,
  /// the previous branch's creds would leak through and we'd send
  /// against the wrong WAWP instance.
  void clearBackendCredentials() {
    if ((_config.instanceId ?? '').isEmpty &&
        (_config.accessToken ?? '').isEmpty) {
      return;
    }
    _config = WhatsAppConfig(
      defaultCountryCode: _config.defaultCountryCode,
      messageTemplate: _config.messageTemplate,
    );
    notifyListeners();
  }

  // --- Public API ---

  /// Render the host's template against a customer + table. Exposed so
  /// the caller can preview the exact text before hitting Send.
  ///
  /// Single-pass substitution: chaining `replaceAll('{name}', ...)`
  /// followed by `replaceAll('{table}', ...)` opens a tiny injection
  /// hole because a customer name containing the literal `{table}`
  /// (or vice versa) would get re-rewritten in the second pass.
  String renderMessage({
    required String customerName,
    required String tableNumber,
  }) {
    final template = _config.messageTemplate.trim().isEmpty
        ? WhatsAppConfig._defaultTemplate
        : _config.messageTemplate;
    return template.replaceAllMapped(
      RegExp(r'\{(name|table)\}'),
      (m) => m.group(1) == 'name' ? customerName : tableNumber,
    );
  }

  /// Normalize whatever the host typed into `966501234567` form.
  /// - Drops spaces, dashes, parentheses.
  /// - Strips a leading `+`.
  /// - Prepends the configured country code (digits-only) when the
  ///   number starts with a local leading zero OR when the number is
  ///   too short to already carry a country prefix.
  String normalizePhone(String raw, {String? countryCodeOverride}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

    String resolved;
    if (hasPlus) {
      resolved = digits;
    } else if (digits.startsWith('00') && digits.length > 2) {
      // ITU "00" prefix — strip to bare international.
      resolved = digits.substring(2);
    } else {
      final cc = _sanitizeCountryCode(
        countryCodeOverride ?? _config.defaultCountryCode,
      );

      if (digits.startsWith(cc) && digits.length > cc.length + 6) {
        // Already carries this country code — trust as-is.
        resolved = digits;
      } else if (digits.startsWith('0')) {
        // Local format "0501234567" → drop the 0 and prepend CC.
        final withoutZero = digits.substring(1);
        // Guard against data-entry mistakes like "0966501234567" (a stray
        // leading 0 before the country code). Without this, we'd strip the
        // 0 AND prepend CC, producing "966966501234567" — a 15-digit phone
        // that WAWP would either reject or, worse, route to the wrong chat.
        if (withoutZero.startsWith(cc) && withoutZero.length > cc.length + 6) {
          resolved = withoutZero;
        } else {
          resolved = '$cc$withoutZero';
        }
      } else if (countryCodeOverride != null &&
          countryCodeOverride.trim().isNotEmpty &&
          digits.length <= 11) {
        // Override means caller knows the country — handles 10-digit
        // Egyptian mobiles the heuristic below would miss.
        resolved = '$cc$digits';
      } else if (digits.length <= 9) {
        // Too short for international — assume local.
        resolved = '$cc$digits';
      } else {
        // Already looks international (e.g. "9665…") — trust it.
        resolved = digits;
      }
    }

    // Repair "double country code" corruption. The backend's
    // `bookings/{id}.user.mobile` endpoint prepends `+966` to every saved
    // mobile regardless of the customer's actual country, so a stored
    // Egyptian number "201090081223" comes back as "+966201090081223" and
    // the dispatcher hands that to us. Detect: digits start with the
    // default CC (`966`) AND the remainder by itself starts with a known
    // foreign country code AND the total length is implausible for that
    // default CC. When all three match, strip the spurious prefix.
    resolved = _stripDoubledCountryCode(resolved);

    // Sanity bounds. ITU-T E.164 caps the international subscriber number
    // at 15 digits, and 8 is the floor for any country's mobile MSISDN
    // including its country code (e.g. UK 44+7… = 11). Anything outside
    // this window is corrupt data — return empty so `sendInvoicePdf`
    // surfaces `invalid_phone` to the UI instead of letting WAWP fail
    // with an opaque HTTP 400.
    if (resolved.length < 8 || resolved.length > 15) {
      return '';
    }
    return resolved;
  }

  /// Strip a leading Saudi (`966`) country code when it was wrongly
  /// prepended on top of an already-international number. Fires when:
  ///   * The inner number begins with one of [_knownForeignCcs] — the
  ///     `+966` was stacked on top of a foreign customer.
  ///   * The inner number itself begins with `966` — the booking
  ///     endpoint stacked the Saudi prefix on top of a Saudi number
  ///     that was already correctly formatted.
  /// Otherwise (e.g. a real `+9665…` Saudi mobile) returns the digits
  /// unchanged so we never corrupt valid numbers.
  static String _stripDoubledCountryCode(String digits) {
    const sa = '966';
    if (!digits.startsWith(sa) || digits.length <= sa.length + 7) {
      return digits;
    }
    final inner = digits.substring(sa.length);
    // Self-match — "966966…" is almost certainly the booking-endpoint
    // double-prefix bug, since Saudi mobiles never exceed 12 digits.
    if (inner.startsWith(sa) && inner.length - sa.length >= 7) {
      return inner;
    }
    for (final cc in _knownForeignCcs) {
      if (inner.startsWith(cc) && inner.length - cc.length >= 6) {
        return inner;
      }
    }
    return digits;
  }

  /// Country dialing codes the cashier could legitimately serve other
  /// than Saudi. Used by [_stripDoubledCountryCode] to differentiate
  /// "real Saudi number" from "Saudi prefix mistakenly stacked on a
  /// foreign number".
  ///
  /// **NANP `1` is deliberately excluded** — Saudi landline numbers
  /// start with `1` after the country code (Riyadh `+966 11…`, Jeddah
  /// `+966 12…`, …). Including `1` here would misread real Saudi
  /// landlines as "Saudi prefix stacked on a US/Canada number" and
  /// strip the leading `966`, corrupting valid numbers. The cashier
  /// app doesn't serve US/Canada anyway, so the trade-off favours
  /// preserving Saudi landlines.
  static const List<String> _knownForeignCcs = <String>[
    '971', '962', '961', '964', '963', '970', '967',
    '249', '218', '216', '213', '212', '222', '252', '253', '269',
    '973', '968', '974', '965', // Gulf neighbours
    '20', // Egypt
    '34', // Spain
    '90', // Turkey
    '92', // Pakistan
    '91', // India
    '44', // UK
    '33', // France
    '49', // Germany
  ];

  /// Strip everything except digits from a country code string. Falls
  /// back to `966` (Saudi) when the input sanitizes to empty so we never
  /// produce a phone without a country prefix — that path otherwise
  /// silently sends "+0501234567" to WAWP and gets rejected.
  static String _sanitizeCountryCode(String cc) {
    final digits = cc.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? '966' : digits;
  }

  /// Main send method — goes through the WAWP HTTP API only. There is no
  /// `wa.me` deep-link fallback: if the branch has no WAWP credentials, or
  /// the API call fails, this returns a failure result and the UI surfaces
  /// a "something went wrong, contact support" message. SMS is not
  /// supported either — every notification goes through the WAWP API.
  Future<WhatsAppSendResult> sendTableReady({
    required String rawPhone,
    required String customerName,
    required String tableNumber,
    String? countryCodeOverride,
  }) async {
    final phone = normalizePhone(
      rawPhone,
      countryCodeOverride: countryCodeOverride,
    );
    if (phone.isEmpty) {
      return const WhatsAppSendResult.failure('invalid_phone');
    }

    if (!_config.isApiReady) {
      debugPrint('🟢 [WAWP/text] isApiReady=false — no WAWP credentials, aborting');
      return const WhatsAppSendResult.failure('wawp_not_configured');
    }

    final message = renderMessage(
      customerName: customerName,
      tableNumber: tableNumber,
    );

    final apiResult = await _sendViaWawp(phone, message);
    if (!apiResult.ok) {
      debugPrint('🟢 [WAWP/text] API leg failed (${apiResult.errorMessage})');
    }
    return apiResult;
  }

  /// Send an invoice PDF directly through WAWP — same architecture as
  /// [sendTableReady]: app talks to WAWP without going through the
  /// backend. Either [pdfBytes] (preferred — sends inline base64) or
  /// [pdfUrl] (the public URL path) MUST be set. Bytes win when both are
  /// provided.
  ///
  /// **API only — no `wa.me` fallback.** If WAWP credentials are missing
  /// or the API call fails, this returns a failure result. We never open
  /// a `wa.me` deep link, because a wrong customer phone would silently
  /// route the host to someone else's chat.
  ///
  /// Bytes path: WAWP receives the document directly in the request body
  /// as base64 — no public hosting required. Recommended whenever the PDF
  /// is generated client-side ([InvoiceHtmlPdfService]) so we don't depend
  /// on a backend upload step that may or may not exist.
  ///
  /// URL path: WAWP fetches the PDF server-side, so the URL must be
  /// publicly reachable (no auth headers, no localhost).
  Future<WhatsAppSendResult> sendInvoicePdf({
    required String rawPhone,
    required String caption,
    Uint8List? pdfBytes,
    String? pdfUrl,
    String filename = 'invoice.pdf',
    String? countryCodeOverride,
  }) async {
    final phone = normalizePhone(
      rawPhone,
      countryCodeOverride: countryCodeOverride,
    );
    if (phone.isEmpty) {
      return const WhatsAppSendResult.failure('invalid_phone');
    }
    final hasBytes = pdfBytes != null && pdfBytes.isNotEmpty;
    final hasUrl = pdfUrl != null && pdfUrl.trim().isNotEmpty;
    if (!hasBytes && !hasUrl) {
      return const WhatsAppSendResult.failure('missing_pdf_payload');
    }

    if (!_config.isApiReady) {
      return const WhatsAppSendResult.failure('wawp_not_configured');
    }

    return _sendPdfViaWawp(
      phone: phone,
      pdfBytes: hasBytes ? pdfBytes : null,
      pdfUrl: hasBytes ? null : pdfUrl!.trim(),
      filename: filename,
      caption: caption,
    );
  }

  // --- Internals ---

  Future<WhatsAppSendResult> _sendViaWawp(String phone, String message) async {
    debugPrint('🟢 [WAWP/text] POST $_apiEndpoint  chatId="$phone" '
        'instanceLen=${(_config.instanceId ?? '').length} '
        'tokenLen=${(_config.accessToken ?? '').length} msgLen=${message.length}');
    try {
      final response = await http
          .post(
            Uri.parse(_apiEndpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'instance_id': _config.instanceId,
              'access_token': _config.accessToken,
              'chatId': phone,
              'message': message,
            }),
          )
          .timeout(_apiTimeout);

      final bodySnippet = response.body.length > 400
          ? '${response.body.substring(0, 400)}…'
          : response.body;
      debugPrint('🟢 [WAWP/text] HTTP ${response.statusCode} — body: $bodySnippet');

      final statusOk = response.statusCode >= 200 && response.statusCode < 300;
      if (!statusOk) {
        developer.log(
          'WhatsAppService: WAWP returned ${response.statusCode} — ${response.body}',
        );
        return WhatsAppSendResult.failure('wawp_http_${response.statusCode}');
      }

      // Parse JSON defensively — a warning response can still come back as 200.
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final status = (body['status'] ?? body['success'])?.toString();
          if (status != null &&
              (status == 'false' ||
                  status == 'error' ||
                  status == '0')) {
            final reason =
                body['message']?.toString() ?? 'wawp_body_error';
            developer.log('WhatsAppService: WAWP body error — $reason');
            debugPrint('🟢 [WAWP/text] body says failed — $reason');
            return WhatsAppSendResult.failure(reason);
          }
        }
      } catch (_) {
        // Non-JSON body — treat 2xx as success.
      }
      debugPrint('🟢 [WAWP/text] OK ✅');
      return const WhatsAppSendResult.apiOk();
    } on TimeoutException {
      debugPrint('🟢 [WAWP/text] TIMEOUT after ${_apiTimeout.inSeconds}s');
      return const WhatsAppSendResult.failure('wawp_timeout');
    } catch (e, st) {
      developer.log(
        'WhatsAppService: WAWP call threw',
        error: e,
        stackTrace: st,
      );
      debugPrint('🟢 [WAWP/text] EXCEPTION: $e');
      return const WhatsAppSendResult.failure('wawp_exception');
    }
  }

  Future<WhatsAppSendResult> _sendPdfViaWawp({
    required String phone,
    required String filename,
    required String caption,
    Uint8List? pdfBytes,
    String? pdfUrl,
  }) async {
    // V2 PDF endpoint: creds on query string, file payload under `file` object.
    final uri = Uri.parse(_pdfEndpoint).replace(queryParameters: {
      'instance_id': _config.instanceId ?? '',
      'access_token': _config.accessToken ?? '',
    });
    final filePayload = pdfBytes != null && pdfBytes.isNotEmpty
        ? {
            'data': base64Encode(pdfBytes),
            'filename': filename,
            'mimetype': 'application/pdf',
          }
        : {
            'url': pdfUrl,
            'filename': filename,
            'mimetype': 'application/pdf',
          };
    try {
      final response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'instance_id': _config.instanceId,
              'access_token': _config.accessToken,
              'chatId': phone,
              'file': filePayload,
              'caption': caption,
            }),
          )
          .timeout(_mediaTimeout);

      final statusOk = response.statusCode >= 200 && response.statusCode < 300;
      if (!statusOk) {
        developer.log(
          'WhatsAppService: WAWP PDF returned ${response.statusCode} — ${response.body}',
        );
        return WhatsAppSendResult.failure('wawp_http_${response.statusCode}');
      }
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final status = (body['status'] ?? body['success'])?.toString();
          if (status != null &&
              (status == 'false' || status == 'error' || status == '0')) {
            final reason = body['message']?.toString() ?? 'wawp_body_error';
            developer.log('WhatsAppService: WAWP PDF body error — $reason');
            return WhatsAppSendResult.failure(reason);
          }
        }
      } catch (_) {
        // Non-JSON 2xx → success.
      }
      return const WhatsAppSendResult.apiOk();
    } on TimeoutException {
      return const WhatsAppSendResult.failure('wawp_timeout');
    } catch (e, st) {
      developer.log(
        'WhatsAppService: WAWP PDF call threw',
        error: e,
        stackTrace: st,
      );
      return const WhatsAppSendResult.failure('wawp_exception');
    }
  }

}

final whatsAppService = WhatsAppService();
