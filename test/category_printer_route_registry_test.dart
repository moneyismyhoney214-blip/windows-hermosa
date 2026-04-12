import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/category_printer_route_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stores and resolves explicit category assignments', () async {
    final registry = CategoryPrinterRouteRegistry();
    await registry.initialize();

    await registry.setCategoryAssignmentsForPrinter(
      'printer:1',
      <String>['22', '43'],
    );
    await registry.setCategoryAssignmentsForPrinter(
      'printer:2',
      <String>['27'],
    );

    final category43 = registry.resolvePrinterIdsForCategoryId(
      categoryId: '43',
      availablePrinterIds: <String>['printer:1', 'printer:2'],
    );
    final category27 = registry.resolvePrinterIdsForCategoryId(
      categoryId: '27',
      availablePrinterIds: <String>['printer:1', 'printer:2'],
    );

    expect(category43, <String>['printer:1']);
    expect(category27, <String>['printer:2']);
  });

  test('ignores empty category ids and clears assignments', () async {
    final registry = CategoryPrinterRouteRegistry();
    await registry.initialize();

    await registry.setCategoryAssignmentsForPrinter(
      'printer:3',
      <String>['', '  ', '50'],
    );
    expect(registry.categoryIdsForPrinter('printer:3'), <String>['50']);

    await registry.clearPrinterAssignments('printer:3');
    expect(registry.categoryIdsForPrinter('printer:3'), isEmpty);
  });

  test('persists category assignments across instances', () async {
    final first = CategoryPrinterRouteRegistry();
    await first.initialize();
    await first.setCategoryAssignmentsForPrinter(
      'printer:9',
      <String>['60', '61'],
    );

    final second = CategoryPrinterRouteRegistry();
    await second.initialize();
    expect(second.categoryIdsForPrinter('printer:9'), <String>['60', '61']);
  });

  test('assignCategoryToPrinter keeps one-printer-per-category mapping',
      () async {
    final registry = CategoryPrinterRouteRegistry();
    await registry.initialize();
    await registry
        .setCategoryAssignmentsForPrinter('printer:1', <String>['44']);
    await registry
        .setCategoryAssignmentsForPrinter('printer:2', <String>['55']);

    await registry.assignCategoryToPrinter(
      categoryId: '44',
      printerId: 'printer:2',
    );

    expect(registry.categoryIdsForPrinter('printer:1'), isEmpty);
    expect(registry.categoryIdsForPrinter('printer:2'), <String>['44', '55']);

    await registry.assignCategoryToPrinter(categoryId: '44', printerId: null);

    expect(registry.categoryIdsForPrinter('printer:2'), <String>['55']);
    expect(
      registry.resolveSinglePrinterIdForCategoryId(
        categoryId: '44',
        availablePrinterIds: <String>['printer:1', 'printer:2'],
      ),
      isNull,
    );
  });
}
