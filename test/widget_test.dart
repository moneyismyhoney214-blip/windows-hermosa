import 'package:flutter_test/flutter_test.dart';

import 'package:hermosa_pos/models.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';

void main() {
  setUp(() {
    ApiConstants.branchId = 87;
  });

  group('API Models Parsing Tests', () {
    test('Parses Meals/Products JSON correctly', () {
      // Sample JSON from API response
      final mockResponse = {
        "data": [
          {
            "id": 1244,
            "name": "V 60 Cold",
            "unit_price": 10,
            "category_id": 5,
            "category_name": "قهوة",
            "image": "https://example.com/image.jpg",
            "is_active": true,
            "extras": [
              {"id": "1", "name": "إكسترا شوت", "price": 4}
            ]
          }
        ]
      };

      // Verify Model Parsing
      final productJson =
          (mockResponse['data'] as List)[0] as Map<String, dynamic>;
      final product = Product.fromJson(productJson);

      expect(product.id, '1244'); // Should parse int to String
      expect(product.name, 'V 60 Cold');
      expect(product.price, 10.0); // Mapped from unit_price
      expect(product.category, 'قهوة'); // Mapped from category_name
      expect(product.isActive, true);
      expect(product.extras.length, 1);
      expect(product.extras[0].name, 'إكسترا شوت');
      expect(product.extras[0].price, 4.0);
    });

    test('Parses Categories JSON correctly', () {
      final mockResponse = {
        "data": [
          {"id": 5, "name": "قهوة", "type": "meals", "parent_id": null}
        ]
      };

      final categoryJson =
          (mockResponse['data'] as List)[0] as Map<String, dynamic>;
      final category = CategoryModel.fromJson(categoryJson);

      expect(category.id, '5'); // Should parse int to String
      expect(category.name, 'قهوة');
      expect(category.type, 'meals');
      expect(category.parentId, null);
    });

    test('Parses Tables JSON correctly', () {
      final mockResponse = {
        "data": [
          {
            "id": 50,
            "number": "1",
            "seats": 4,
            "floor": "f1",
            "status": "available",
            "waiter_name": null,
            "occupied_minutes": 0
          }
        ]
      };

      final tableJson =
          (mockResponse['data'] as List)[0] as Map<String, dynamic>;
      final table = TableItem.fromJson(tableJson);

      expect(table.id, '50');
      expect(table.number, '1');
      expect(table.seats, 4);
      expect(table.floorId, 'f1'); // Mapped from floor
      expect(table.status, TableStatus.available);
    });
  });

  group('API Constants Tests', () {
    test('Base URL is correct', () {
      expect(ApiConstants.baseUrl, 'https://portal.hermosaapp.com');
    });

    test('Branch ID is configured', () {
      expect(ApiConstants.branchId, 87);
    });

    test('Endpoints are properly formatted', () {
      // productsEndpoint now points to /products
      expect(ApiConstants.productsEndpoint,
          contains('/seller/branches/87/products'));
      // mealsEndpoint points to /meals
      expect(ApiConstants.mealsEndpoint, contains('/seller/branches/87/meals'));
      expect(ApiConstants.tablesEndpoint,
          contains('/seller/branches/87/restaurantTables'));
    });
  });
}
