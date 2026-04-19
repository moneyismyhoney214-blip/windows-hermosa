import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (data) async {
      if (data == null || data.isEmpty) return;

      final dir = Directory('build/performance_results');
      if (!dir.existsSync()) dir.createSync(recursive: true);

      // 1. Extract and save Chrome Trace (for DevTools)
      final chromeTrace = data.remove('_chrome_trace');
      if (chromeTrace != null) {
        final traceFile = File('${dir.path}/app_trace.json');
        traceFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(chromeTrace),
        );
        print('');
        print('╔══════════════════════════════════════════════════════════╗');
        print('║  📁 Chrome Trace saved:                                  ║');
        print('║  build/performance_results/app_trace.json                ║');
        print('║                                                          ║');
        print('║  👉 Open in browser: chrome://tracing                    ║');
        print('║  👉 Or: Flutter DevTools → Performance → Import          ║');
        print('╚══════════════════════════════════════════════════════════╝');
      }

      // 2. Save summary report
      final reportFile = File('${dir.path}/performance_report.json');
      reportFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(data),
      );
      print('  📁 Summary: build/performance_results/performance_report.json');

      // 3. Print summary table
      print('');
      print('  ┌──────────────────────┬────────┬────────┐');
      print('  │ Test                 │ Frames │ Jank   │');
      print('  ├──────────────────────┼────────┼────────┤');
      for (final entry in data.entries) {
        if (entry.value is Map) {
          final m = entry.value as Map;
          final label = (m['label'] ?? entry.key).toString().padRight(20);
          final frames = (m['total_frames'] ?? '?').toString().padLeft(5);
          final jank = (m['jank_pct'] ?? '?').toString().padLeft(6);
          print('  │ $label │ $frames │ $jank │');
        }
      }
      print('  └──────────────────────┴────────┴────────┘');
    },
  );
}
