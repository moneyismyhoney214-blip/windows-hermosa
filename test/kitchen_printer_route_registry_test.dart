import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/kitchen_printer_route_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('uses explicit mapping when available', () async {
    final registry = KitchenPrinterRouteRegistry();
    await registry.initialize();

    await registry.setKitchenAssignmentsForPrinter('printer:1', <int>[7, 8]);
    await registry.setKitchenAssignmentsForPrinter('printer:2', <int>[9]);

    final resolved = registry.resolvePrinterIdsForKitchen(
      kitchenId: 8,
      availablePrinterIds: <String>['printer:1', 'printer:2'],
      knownKitchenIds: <int>[7, 8, 9],
    );

    expect(resolved, <String>['printer:1']);
  });

  test('balances deterministically when no manual mapping exists', () async {
    final registry = KitchenPrinterRouteRegistry();
    await registry.initialize();

    final kitchen7 = registry.resolvePrinterIdsForKitchen(
      kitchenId: 7,
      availablePrinterIds: <String>['printer:a', 'printer:b'],
      knownKitchenIds: <int>[7, 8, 9],
    );
    final kitchen8 = registry.resolvePrinterIdsForKitchen(
      kitchenId: 8,
      availablePrinterIds: <String>['printer:a', 'printer:b'],
      knownKitchenIds: <int>[7, 8, 9],
    );
    final kitchen9 = registry.resolvePrinterIdsForKitchen(
      kitchenId: 9,
      availablePrinterIds: <String>['printer:a', 'printer:b'],
      knownKitchenIds: <int>[7, 8, 9],
    );

    expect(kitchen7, <String>['printer:a']);
    expect(kitchen8, <String>['printer:b']);
    expect(kitchen9, <String>['printer:a']);
  });

  test('prefers unassigned printers for kitchens without explicit mapping',
      () async {
    final registry = KitchenPrinterRouteRegistry();
    await registry.initialize();

    await registry.setKitchenAssignmentsForPrinter('printer:1', <int>[7]);

    final resolved = registry.resolvePrinterIdsForKitchen(
      kitchenId: 9,
      availablePrinterIds: <String>['printer:1', 'printer:2', 'printer:3'],
      knownKitchenIds: <int>[7, 9],
    );

    expect(resolved.length, 1);
    expect(
        resolved.first == 'printer:2' || resolved.first == 'printer:3', true);
  });

  test('persists assignments across instances', () async {
    final registry = KitchenPrinterRouteRegistry();
    await registry.initialize();
    await registry.setKitchenAssignmentsForPrinter('printer:8', <int>[11, 12]);

    final reloaded = KitchenPrinterRouteRegistry();
    await reloaded.initialize();

    expect(reloaded.kitchenIdsForPrinter('printer:8'), <int>[11, 12]);
  });
}
