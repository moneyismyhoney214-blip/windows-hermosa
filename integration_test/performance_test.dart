// =============================================================================
// CASHEIR APP - Performance Profiling Test
// =============================================================================
// Run:
//   flutter drive --driver=test_driver/perf_test_driver.dart \
//     --target=integration_test/performance_test.dart \
//     --profile --no-dds -d R9KTA024LQP
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hermosa_pos/main.dart' as app;
import 'package:hermosa_pos/widgets/product_card.dart';

/// Frame timing collector using SchedulerBinding (no VM Service needed).
class FrameTimingCollector {
  final List<FrameTiming> timings = [];
  void Function(List<FrameTiming>)? _callback;

  void start() {
    timings.clear();
    _callback = (List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(_callback!);
  }

  void stop() {
    if (_callback != null) {
      SchedulerBinding.instance.removeTimingsCallback(_callback!);
      _callback = null;
    }
  }

  Map<String, dynamic> summarize(String label) {
    if (timings.isEmpty) return {'label': label, 'error': 'no frames captured'};

    final buildMs = timings.map((t) => t.buildDuration.inMicroseconds / 1000.0).toList()..sort();
    final rasterMs = timings.map((t) => t.rasterDuration.inMicroseconds / 1000.0).toList()..sort();
    final totalMs = timings.map((t) =>
        (t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds) / 1000.0).toList()..sort();

    double p(List<double> sorted, double pct) {
      final idx = ((pct / 100) * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
      return sorted[idx];
    }

    final total = timings.length;
    final jank = totalMs.where((t) => t > 16.67).length;
    final severe = totalMs.where((t) => t > 33.34).length;

    return {
      'label': label,
      'total_frames': total,
      'jank_frames': jank,
      'severe_jank': severe,
      'jank_pct': '${(jank / total * 100).toStringAsFixed(1)}%',
      'build_ms': {'p50': p(buildMs, 50).toStringAsFixed(2), 'p90': p(buildMs, 90).toStringAsFixed(2), 'p99': p(buildMs, 99).toStringAsFixed(2), 'worst': buildMs.last.toStringAsFixed(2)},
      'raster_ms': {'p50': p(rasterMs, 50).toStringAsFixed(2), 'p90': p(rasterMs, 90).toStringAsFixed(2), 'p99': p(rasterMs, 99).toStringAsFixed(2), 'worst': rasterMs.last.toStringAsFixed(2)},
      'total_ms': {'p50': p(totalMs, 50).toStringAsFixed(2), 'p90': p(totalMs, 90).toStringAsFixed(2), 'p99': p(totalMs, 99).toStringAsFixed(2), 'worst': totalMs.last.toStringAsFixed(2)},
    };
  }

  /// Convert FrameTiming data to Chrome Trace Event format for DevTools.
  List<Map<String, dynamic>> toChromeTraceEvents(String label) {
    final events = <Map<String, dynamic>>[];
    // Use a synthetic timestamp based on index since raw timestamps
    // aren't easily accessible without FramePhase enum.
    var syntheticTs = 0;
    for (int i = 0; i < timings.length; i++) {
      final t = timings[i];
      final buildDurUs = t.buildDuration.inMicroseconds;
      final rasterDurUs = t.rasterDuration.inMicroseconds;
      final buildStartUs = syntheticTs;
      final rasterStartUs = syntheticTs + buildDurUs;

      // Build phase
      events.add({
        'name': '$label Build',
        'cat': 'flutter',
        'ph': 'X',
        'ts': buildStartUs,
        'dur': buildDurUs,
        'pid': 1,
        'tid': 1,
        'args': {'frame': i, 'build_ms': (buildDurUs / 1000).toStringAsFixed(2)},
      });

      // Raster phase
      events.add({
        'name': '$label Raster',
        'cat': 'flutter',
        'ph': 'X',
        'ts': rasterStartUs,
        'dur': rasterDurUs,
        'pid': 1,
        'tid': 2,
        'args': {'frame': i, 'raster_ms': (rasterDurUs / 1000).toStringAsFixed(2)},
      });

      // Mark jank frames
      final totalMs = (buildDurUs + rasterDurUs) / 1000.0;
      if (totalMs > 16.67) {
        events.add({
          'name': 'JANK ${totalMs.toStringAsFixed(1)}ms',
          'cat': 'jank',
          'ph': 'i',
          's': 'g',
          'ts': buildStartUs,
          'pid': 1,
          'tid': 1,
          'args': {'total_ms': totalMs.toStringAsFixed(2), 'frame': i},
        });
      }

      // Advance synthetic clock (16.67ms per frame = 60fps target)
      syntheticTs += (buildDurUs + rasterDurUs).clamp(16667, 999999);
    }
    return events;
  }

  void printReport(String label) {
    final s = summarize(label);
    if (s.containsKey('error')) {
      debugPrint('⚠️  $label: ${s['error']}');
      return;
    }
    final pad = (dynamic v) => v.toString().padLeft(7);
    debugPrint('');
    debugPrint('┌─────────────────────────────────────────────────────┐');
    debugPrint('│  $label');
    debugPrint('├─────────────────────────────────────────────────────┤');
    debugPrint('│  Frames: ${s['total_frames']}  |  Jank: ${s['jank_frames']} (${s['jank_pct']})  |  Severe: ${s['severe_jank']}');
    debugPrint('│            p50      p90      p99      worst');
    debugPrint('│  Build:  ${pad(s['build_ms']['p50'])}  ${pad(s['build_ms']['p90'])}  ${pad(s['build_ms']['p99'])}  ${pad(s['build_ms']['worst'])} ms');
    debugPrint('│  Raster: ${pad(s['raster_ms']['p50'])}  ${pad(s['raster_ms']['p90'])}  ${pad(s['raster_ms']['p99'])}  ${pad(s['raster_ms']['worst'])} ms');
    debugPrint('│  Total:  ${pad(s['total_ms']['p50'])}  ${pad(s['total_ms']['p90'])}  ${pad(s['total_ms']['p99'])}  ${pad(s['total_ms']['worst'])} ms');
    debugPrint('└─────────────────────────────────────────────────────┘');
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Full app performance profiling', (tester) async {
    final collector = FrameTimingCollector();
    final allResults = <String, dynamic>{};
    final allCollectors = <String, FrameTimingCollector>{};

    // ═══════════════════════════════════════════════════════════
    // PHASE 1: Launch app
    // ═══════════════════════════════════════════════════════════
    debugPrint('🚀 Launching app...');
    collector.start();
    final startupSw = Stopwatch()..start();

    app.main();

    // Wait for splash/login to settle (up to 20s)
    await tester.pumpAndSettle(const Duration(seconds: 20));
    // Extra pumps in case animations are still running
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    collector.stop();
    startupSw.stop();
    debugPrint('⏱️  Startup: ${startupSw.elapsedMilliseconds}ms');
    collector.printReport('1. APP STARTUP');
    allResults['01_startup'] = {
      ...collector.summarize('APP STARTUP'),
      'wall_time_ms': startupSw.elapsedMilliseconds,
    };
    allCollectors['startup'] = FrameTimingCollector()..timings.addAll(collector.timings);

    // ═══════════════════════════════════════════════════════════
    // PHASE 2: Login
    // ═══════════════════════════════════════════════════════════
    debugPrint('🔐 Attempting login...');

    // Find email field
    final textFields = find.byType(TextField);
    final textFieldCount = textFields.evaluate().length;
    debugPrint('   Found $textFieldCount TextFields');

    if (textFieldCount >= 2) {
      // Enter email
      await tester.enterText(textFields.at(0), 'tikanah200@gmail.com');
      await tester.pump(const Duration(milliseconds: 300));

      // Enter password
      await tester.enterText(textFields.at(1), '123456');
      await tester.pump(const Duration(milliseconds: 300));

      // Find and tap login button
      // Try common button types
      final elevatedButtons = find.byType(ElevatedButton);
      final materialButtons = find.byType(MaterialButton);
      final inkWells = find.byType(InkWell);

      Finder? loginButton;
      if (elevatedButtons.evaluate().isNotEmpty) {
        loginButton = elevatedButtons.first;
        debugPrint('   Found ElevatedButton for login');
      } else if (materialButtons.evaluate().isNotEmpty) {
        loginButton = materialButtons.first;
        debugPrint('   Found MaterialButton for login');
      }

      // Also try finding by text
      final loginTextFinder = find.text('تسجيل الدخول');
      final loginTextEn = find.text('Login');
      final loginTextEn2 = find.text('Sign In');

      if (loginTextFinder.evaluate().isNotEmpty) {
        loginButton = loginTextFinder.first;
        debugPrint('   Found login button by Arabic text');
      } else if (loginTextEn.evaluate().isNotEmpty) {
        loginButton = loginTextEn.first;
      } else if (loginTextEn2.evaluate().isNotEmpty) {
        loginButton = loginTextEn2.first;
      }

      if (loginButton != null) {
        collector.start();
        final loginSw = Stopwatch()..start();

        await tester.tap(loginButton);
        // Wait for login + main screen load (up to 30s)
        await tester.pumpAndSettle(const Duration(seconds: 30));
        // Extra settle
        for (int i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }

        collector.stop();
        loginSw.stop();
        debugPrint('⏱️  Login->MainScreen: ${loginSw.elapsedMilliseconds}ms');
        collector.printReport('2. LOGIN -> MAIN SCREEN');
        allResults['02_login'] = {
          ...collector.summarize('LOGIN -> MAIN SCREEN'),
          'wall_time_ms': loginSw.elapsedMilliseconds,
        };
        allCollectors['login'] = FrameTimingCollector()..timings.addAll(collector.timings);
      } else {
        debugPrint('⚠️  Could not find login button');
      }
    } else if (textFieldCount == 0) {
      debugPrint('   No TextFields — might already be logged in');
      // If already on main screen, skip login
      await tester.pumpAndSettle(const Duration(seconds: 5));
    }

    // ═══════════════════════════════════════════════════════════
    // Wait for main screen to be fully loaded
    // ═══════════════════════════════════════════════════════════
    await tester.pumpAndSettle(const Duration(seconds: 5));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    // Check if we're on the main screen
    final productCards = find.byType(ProductCard);
    final scrollViews = find.byType(CustomScrollView);
    debugPrint('📱 Main screen check: ${productCards.evaluate().length} products, ${scrollViews.evaluate().length} scrollViews');

    // ═══════════════════════════════════════════════════════════
    // PHASE 3: Product Grid Scrolling
    // ═══════════════════════════════════════════════════════════
    if (scrollViews.evaluate().isNotEmpty) {
      debugPrint('📜 Testing product grid scrolling...');
      collector.start();

      for (int i = 0; i < 5; i++) {
        await tester.fling(scrollViews.first, const Offset(0, -600), 2500);
        await tester.pumpAndSettle();
      }
      for (int i = 0; i < 5; i++) {
        await tester.fling(scrollViews.first, const Offset(0, 600), 2500);
        await tester.pumpAndSettle();
      }

      collector.stop();
      collector.printReport('3. PRODUCT GRID SCROLL');
      allResults['03_scroll'] = collector.summarize('PRODUCT GRID SCROLL');
      allCollectors['scroll'] = FrameTimingCollector()..timings.addAll(collector.timings);
    } else {
      debugPrint('⚠️  No CustomScrollView — trying any Scrollable');
      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isNotEmpty) {
        collector.start();
        for (int i = 0; i < 3; i++) {
          await tester.fling(scrollables.first, const Offset(0, -400), 2000);
          await tester.pumpAndSettle();
        }
        collector.stop();
        collector.printReport('3. SCROLLABLE SCROLL');
        allResults['03_scroll'] = collector.summarize('SCROLLABLE SCROLL');
        allCollectors['scroll'] = FrameTimingCollector()..timings.addAll(collector.timings);
      }
    }

    // ═══════════════════════════════════════════════════════════
    // PHASE 4: Category Switching
    // ═══════════════════════════════════════════════════════════
    final catBar = find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(InkWell),
    );
    final catCount = catBar.evaluate().length;
    debugPrint('📂 Found $catCount category items');

    if (catCount >= 2) {
      debugPrint('🔄 Testing category switching...');
      collector.start();

      final taps = catCount.clamp(2, 6);
      for (int i = 1; i < taps; i++) {
        await tester.tap(catBar.at(i));
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      await tester.tap(catBar.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      collector.stop();
      collector.printReport('4. CATEGORY SWITCH');
      allResults['04_category_switch'] = collector.summarize('CATEGORY SWITCH');
      allCollectors['category'] = FrameTimingCollector()..timings.addAll(collector.timings);
    }

    // ═══════════════════════════════════════════════════════════
    // PHASE 5: Add to Cart
    // ═══════════════════════════════════════════════════════════
    final freshProducts = find.byType(ProductCard);
    final prodCount = freshProducts.evaluate().length;
    debugPrint('🛒 Found $prodCount products for cart test');

    if (prodCount > 0) {
      debugPrint('➕ Testing add to cart...');
      collector.start();

      final addCount = prodCount.clamp(1, 5);
      for (int i = 0; i < addCount; i++) {
        await tester.tap(freshProducts.at(i));
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      collector.stop();
      collector.printReport('5. ADD TO CART');
      allResults['05_add_to_cart'] = collector.summarize('ADD TO CART');
      allCollectors['cart'] = FrameTimingCollector()..timings.addAll(collector.timings);
    }

    // ═══════════════════════════════════════════════════════════
    // PHASE 6: Rapid Stress Test (category switch + tap product)
    // ═══════════════════════════════════════════════════════════
    if (catCount >= 2) {
      debugPrint('💥 Running rapid stress test...');
      collector.start();

      for (int round = 0; round < 4; round++) {
        await tester.tap(catBar.at((round + 1) % catCount));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final prods = find.byType(ProductCard);
        if (prods.evaluate().isNotEmpty) {
          await tester.tap(prods.first);
          await tester.pump(const Duration(milliseconds: 50));
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }

      await tester.tap(catBar.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      collector.stop();
      collector.printReport('6. RAPID STRESS TEST');
      allResults['06_stress_test'] = collector.summarize('RAPID STRESS TEST');
      allCollectors['stress'] = FrameTimingCollector()..timings.addAll(collector.timings);
    }

    // ═══════════════════════════════════════════════════════════
    // DONE: Report results + Chrome Trace
    // ═══════════════════════════════════════════════════════════
    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════════════╗');
    debugPrint('║           ✅ ALL PERFORMANCE TESTS COMPLETE           ║');
    debugPrint('╚══════════════════════════════════════════════════════╝');

    // Build Chrome Trace JSON from all collected frame timings
    final allTraceEvents = <Map<String, dynamic>>[];
    allTraceEvents.addAll(allCollectors['startup']?.toChromeTraceEvents('Startup') ?? []);
    allTraceEvents.addAll(allCollectors['login']?.toChromeTraceEvents('Login') ?? []);
    allTraceEvents.addAll(allCollectors['scroll']?.toChromeTraceEvents('Scroll') ?? []);
    allTraceEvents.addAll(allCollectors['category']?.toChromeTraceEvents('CategorySwitch') ?? []);
    allTraceEvents.addAll(allCollectors['cart']?.toChromeTraceEvents('AddToCart') ?? []);
    allTraceEvents.addAll(allCollectors['stress']?.toChromeTraceEvents('StressTest') ?? []);

    final chromeTrace = {'traceEvents': allTraceEvents};

    // Pass both the summary and the chrome trace to the driver
    allResults['_chrome_trace'] = chromeTrace;

    debugPrint('');
    debugPrint(const JsonEncoder.withIndent('  ').convert(
      Map.fromEntries(allResults.entries.where((e) => e.key != '_chrome_trace')),
    ));

    binding.reportData = allResults;
  });
}
