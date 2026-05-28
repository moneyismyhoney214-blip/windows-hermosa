import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api/base_client.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../utils/ui_feedback.dart';

/// In-app viewer for the marketing/legal static pages exposed by
/// `portal.hermosaapp.com/staticPages/<slug>`. The same slug is used on
/// the public web site (`v2.hermosaapp.com/pages/<slug>`) — surfaced as
/// an "open in browser" action so the user can read the canonical
/// version when wanted.
///
/// Language follows whatever the user has currently selected in the
/// app — passed through as `Accept-Language` so the API returns the
/// matching locale.
class LegalPageScreen extends StatefulWidget {
  /// API + web slug. Examples: `'privacy-policy'`, `'terms-conditions'`.
  final String slug;

  /// Pre-resolved title used while the API call is in flight. Once the
  /// payload comes back, the API's `title` (which already respects
  /// the `Accept-Language` header) replaces this.
  final String fallbackTitle;

  const LegalPageScreen({
    super.key,
    required this.slug,
    required this.fallbackTitle,
  });

  @override
  State<LegalPageScreen> createState() => _LegalPageScreenState();
}

class _LegalPageScreenState extends State<LegalPageScreen> {
  static const String _webHost = 'https://v2.hermosaapp.com';

  bool _loading = true;
  String? _error;
  String _title = '';
  String _content = '';

  @override
  void initState() {
    super.initState();
    _title = widget.fallbackTitle;
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Route through BaseClient so the request inherits the rest of
      // the app's HTTP setup: TLS pinning, connection pooling, the
      // retry-on-connection-closed handler, and centralised error
      // shaping. `skipGlobalAuth: true` keeps the JWT off this call
      // (public static-pages endpoint, no token required).
      final json = await BaseClient().get(
        '/staticPages/${widget.slug}',
        skipGlobalAuth: true,
      );

      final data = (json is Map && json['data'] is Map)
          ? Map<String, dynamic>.from(json['data'] as Map)
          : <String, dynamic>{};

      final title = data['title']?.toString().trim() ?? '';
      final content = data['content']?.toString() ?? '';
      if (content.isEmpty) {
        throw Exception('empty_content');
      }
      if (!mounted) return;
      setState(() {
        _title = title.isNotEmpty ? title : widget.fallbackTitle;
        _content = content;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openOnWeb() async {
    final lang = translationService.currentLocale.languageCode;
    final uri = Uri.parse('$_webHost/pages/${widget.slug}?lang=$lang');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _showLaunchError();
    } catch (_) {
      if (mounted) _showLaunchError();
    }
  }

  void _showLaunchError() {
    UiFeedback.error(context, translationService.t('error_occurred'));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection:
          translationService.isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: context.appBg,
        appBar: AppBar(
          backgroundColor: context.appHeaderBg,
          foregroundColor: context.appText,
          elevation: 0,
          title: Text(
            _title,
            style: GoogleFonts.tajawal(
              fontWeight: FontWeight.w700,
              color: context.appText,
            ),
          ),
          actions: [
            IconButton(
              tooltip: translationService.t('open_in_browser'),
              onPressed: _openOnWeb,
              icon: const Icon(LucideIcons.externalLink),
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.alertTriangle,
                  size: 48, color: context.appTextMuted),
              const SizedBox(height: 12),
              Text(
                translationService.t('error_occurred'),
                style: GoogleFonts.tajawal(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.appText,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: Text(translationService.t('retry')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.appPrimary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: HtmlWidget(
        _content,
        textStyle: GoogleFonts.tajawal(
          fontSize: 14,
          height: 1.7,
          color: context.appText,
        ),
      ),
    );
  }
}
