import 'package:flutter/material.dart';
import 'display_language_service.dart';

class ReconnectBanner extends StatelessWidget {
  final int seconds;
  final String languageCode;

  const ReconnectBanner({
    super.key,
    required this.seconds,
    required this.languageCode,
  });

  @override
  Widget build(BuildContext context) {
    final title = DisplayLanguageService.t(
      'conn_reconnecting',
      languageCode: languageCode,
    );
    final subtitle = seconds > 0
        ? DisplayLanguageService.t(
            'conn_reconnect_in',
            languageCode: languageCode,
            args: {'seconds': seconds},
          )
        : '';
    final isRtl = DisplayLanguageService.isRtl(languageCode);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  color: Color(0xFFB45309),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF92400E),
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
