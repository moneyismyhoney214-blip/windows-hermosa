import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermosa_pos/locator.dart';
import 'package:hermosa_pos/services/api/product_service.dart';
import 'package:hermosa_pos/services/cache_service.dart';
import 'package:hermosa_pos/services/kds_meal_availability_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    getIt.allowReassignment = true;
    if (!getIt.isRegistered<CacheService>()) {
      getIt.registerLazySingleton<CacheService>(() => CacheService());
    }
    if (!getIt.isRegistered<ProductService>()) {
      getIt.registerLazySingleton<ProductService>(() => ProductService());
    }
  });

  group('KDS Meal Availability Sync Deep Scan', () {
    late KdsMealAvailabilityService service;
    late int notifyCount;

    setUp(() {
      service = KdsMealAvailabilityService();
      notifyCount = 0;
      service.addListener(() {
        notifyCount++;
      });
    });

    test('applies disable using meal_id key', () {
      service.applyKdsRealtimeUpdate({
        'meal_id': '501',
        'meal_name': 'مندي',
        'is_disabled': true,
      });

      expect(service.isMealDisabled('501'), isTrue);
      expect(notifyCount, 1);
    });

    test('applies disable using product_id key', () {
      service.applyKdsRealtimeUpdate({
        'product_id': '601',
        'meal_name': 'مشكل',
        'is_disabled': true,
      });

      expect(service.isMealDisabled('601'), isTrue);
      expect(notifyCount, 1);
    });

    test('applies disable using productId key', () {
      service.applyKdsRealtimeUpdate({
        'productId': '701',
        'meal_name': 'فطيرة',
        'is_disabled': true,
      });

      expect(service.isMealDisabled('701'), isTrue);
      expect(notifyCount, 1);
    });

    test('reenable removes meal from disabled map', () {
      service.applyKdsRealtimeUpdate({
        'meal_id': '801',
        'meal_name': 'كنتاكي',
        'is_disabled': true,
      });
      service.applyKdsRealtimeUpdate({
        'meal_id': '801',
        'meal_name': 'كنتاكي',
        'is_disabled': false,
      });

      expect(service.isMealDisabled('801'), isFalse);
      expect(service.getMealState('801'), isNull);
      expect(notifyCount, 2);
    });

    test('ignores payload with no id keys', () {
      service.applyKdsRealtimeUpdate({
        'meal_name': 'بدون معرف',
        'is_disabled': true,
      });

      expect(service.disabledMeals, isEmpty);
      expect(notifyCount, 0);
    });

    test('stress: 500 rapid mixed toggles keep final state consistent', () {
      const mealCount = 25;
      const iterations = 500;

      // Ground truth map to compare service state after burst updates.
      final expected = <String, bool>{
        for (var i = 0; i < mealCount; i++) '$i': false,
      };

      for (var i = 0; i < iterations; i++) {
        final mealId = '${i % mealCount}';
        final disable = i.isEven;
        final variant = i % 3;
        final payload = switch (variant) {
          0 => {
              'meal_id': mealId,
              'meal_name': 'Meal $mealId',
              'is_disabled': disable,
            },
          1 => {
              'product_id': mealId,
              'meal_name': 'Meal $mealId',
              'is_disabled': disable,
            },
          _ => {
              'productId': mealId,
              'meal_name': 'Meal $mealId',
              'is_disabled': disable,
            },
        };

        expected[mealId] = disable;
        service.applyKdsRealtimeUpdate(payload);
      }

      for (var i = 0; i < mealCount; i++) {
        final id = '$i';
        expect(
          service.isMealDisabled(id),
          expected[id],
          reason: 'Mismatch for meal id $id after burst sync',
        );
      }

      expect(notifyCount, iterations);
    });
  });
}
