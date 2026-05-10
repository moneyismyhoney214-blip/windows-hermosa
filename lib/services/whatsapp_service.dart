import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of a send attempt. Kept compact on purpose — the UI just
/// needs to know "did a message reach (or will reach) the customer"
/// plus a human-readable reason when it didn't.
class WhatsAppSendResult {
  /// True when either the WAWP API accepted the payload OR the device
  /// successfully launched the WhatsApp app for the host to hit "send"
  /// manually.
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
  const WhatsAppSendResult.deepLinkOk(WhatsAppSendChannel channel)
      : this._(true, channel, null);
  const WhatsAppSendResult.failure(String reason)
      : this._(false, WhatsAppSendChannel.none, reason);
}

enum WhatsAppSendChannel { wawpApi, whatsappDeepLink, none }

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

  // WAWP credentials (instanceId/accessToken) are sourced from the
  // backend `/seller/branches/{id}/settings` payload and held in memory
  // only — they are intentionally NOT persisted here.
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

/// Singleton gateway for sending "your table is ready" messages.
///
/// Two-tier pipeline so the host is never stuck:
///   1. WAWP HTTP API — silent, no app switching. Needs credentials.
///   2. `https://wa.me/<phone>?text=...` deep link — opens WhatsApp with
///       the message pre-filled; host taps "send".
///
/// Tier 1 is skipped when WAWP credentials are missing, and falls
/// through to tier 2 when the API returns a non-2xx response.
class WhatsAppService extends ChangeNotifier {
  static final WhatsAppService _instance = WhatsAppService._internal();
  factory WhatsAppService() => _instance;
  WhatsAppService._internal();

  static const String _storageKey = 'whatsapp_wawp_config_v1';
  static const String _apiEndpoint = 'https://api.wawp.net/v2/send/text';
  static const String _pdfEndpoint = 'https://api.wawp.net/v2/send/pdf';
  static const Duration _apiTimeout = Duration(seconds: 12);
  static const Duration _mediaTimeout = Duration(seconds: 25);

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
          // Preserve any in-memory creds that may have been seeded from
          // `/seller/branches/{id}/settings` while we were waiting on
          // prefs. The stored JSON intentionally only carries the
          // user-tuned `defaultCountryCode` + `messageTemplate`; creds
          // live in memory only and would otherwise be wiped by a naive
          // assignment here.
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
    // NOTE: do NOT touch `_initialized` here — that flag is owned by
    // [_load] and toggling it from this seeding path would short-circuit
    // the prefs load, silently losing the user's saved
    // `messageTemplate` + `defaultCountryCode`.
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

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

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

    // Keep only digits (and a leading +).
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

    if (hasPlus) {
      // Already international — just drop the +.
      return digits;
    }

    final cc = _sanitizeCountryCode(
      countryCodeOverride ?? _config.defaultCountryCode,
    );

    // Local format: "0501234567" → drop the 0 and prepend CC.
    if (digits.startsWith('0')) {
      return '$cc${digits.substring(1)}';
    }

    // Too short to be international — assume local.
    if (digits.length <= 9) {
      return '$cc$digits';
    }

    // Already looks international (e.g. "9665…") — trust it.
    return digits;
  }

  /// Strip everything except digits from a country code string. Falls
  /// back to `966` (Saudi) when the input sanitizes to empty so we never
  /// produce a phone without a country prefix — that path otherwise
  /// silently sends "+0501234567" to WAWP and gets rejected.
  static String _sanitizeCountryCode(String cc) {
    final digits = cc.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? '966' : digits;
  }

  /// Main send method. Pipeline: try the WAWP HTTP API first when the
  /// branch has credentials, then fall back to the `wa.me` deep link so
  /// the host can finish manually if the API call fails. SMS is no
  /// longer supported — every notification goes through WhatsApp.
  Future<WhatsAppSendResult> sendTableReady({
    required String rawPhone,
    required String customerName,
    required String tableNumber,
  }) async {
    final phone = normalizePhone(rawPhone);
    if (phone.isEmpty) {
      return const WhatsAppSendResult.failure('invalid_phone');
    }

    final message = renderMessage(
      customerName: customerName,
      tableNumber: tableNumber,
    );

    if (_config.isApiReady) {
      final apiResult = await _sendViaWawp(phone, message);
      if (apiResult.ok) return apiResult;
      // API configured but failed — fall through to deep link so the
      // host can finish the job manually.
    }
    return _openWhatsAppDeepLink(phone, message);
  }

  /// Send an invoice PDF directly through WAWP — same architecture as
  /// [sendTableReady]: app talks to WAWP without going through the
  /// backend. Caller supplies a publicly reachable [pdfUrl] (WAWP fetches
  /// it server-side, so a localhost path or auth-gated URL won't work).
  ///
  /// Falls through to a `wa.me` deep link with the PDF link as text when
  /// the API call fails so the host can finish the send manually.
  /// Either [pdfBytes] (preferred — sends inline base64) or [pdfUrl] (the
  /// public URL path) MUST be set. Bytes win when both are provided.
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

    if (_config.isApiReady) {
      final apiResult = await _sendPdfViaWawp(
        phone: phone,
        pdfBytes: hasBytes ? pdfBytes : null,
        pdfUrl: hasBytes ? null : pdfUrl!.trim(),
        filename: filename,
        caption: caption,
      );
      if (apiResult.ok) return apiResult;
    }
    // Fallback: open WhatsApp with caption (and the URL when we have one)
    // so the host can attach manually if the API leg failed. We don't
    // include the base64 blob in the deep link — it would never fit.
    final trimmedUrl = pdfUrl?.trim() ?? '';
    final deepLinkBody = hasUrl
        ? (caption.trim().isEmpty ? trimmedUrl : '$caption\n$trimmedUrl')
        : caption;
    return _openWhatsAppDeepLink(phone, deepLinkBody);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<WhatsAppSendResult> _sendViaWawp(String phone, String message) async {
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

      final statusOk = response.statusCode >= 200 && response.statusCode < 300;
      if (!statusOk) {
        developer.log(
          'WhatsAppService: WAWP returned ${response.statusCode} — ${response.body}',
        );
        return WhatsAppSendResult.failure('wawp_http_${response.statusCode}');
      }

      // WAWP returns a JSON body — parse defensively since a warning
      // response can still come back with 200.
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
            return WhatsAppSendResult.failure(reason);
          }
        }
      } catch (_) {
        // Body isn't JSON — treat HTTP 2xx as success.
      }
      return const WhatsAppSendResult.apiOk();
    } on TimeoutException {
      return const WhatsAppSendResult.failure('wawp_timeout');
    } catch (e, st) {
      developer.log(
        'WhatsAppService: WAWP call threw — falling through to deep link',
        error: e,
        stackTrace: st,
      );
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
    // V2 PDF endpoint expects credentials on the query string and the
    // file payload nested under a `file` object — same structure as the
    // image/document endpoints.
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
        // Non-JSON 2xx — treat as success.
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

  Future<WhatsAppSendResult> _openWhatsAppDeepLink(
    String phone,
    String message,
  ) async {
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) {
        return const WhatsAppSendResult.deepLinkOk(
          WhatsAppSendChannel.whatsappDeepLink,
        );
      }
    } catch (e, st) {
      developer.log(
        'WhatsAppService: WhatsApp deep-link failed',
        error: e,
        stackTrace: st,
      );
    }
    return const WhatsAppSendResult.failure('wa_not_installed');
  }

}

final whatsAppService = WhatsAppService();
