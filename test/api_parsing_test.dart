import 'package:flutter_test/flutter_test.dart';

import 'package:hermosa_pos/models.dart';

void main() {
  group('API Parsing Tests', () {
    test('Parses Meals JSON correctly', () {
      // Sample JSON from API
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

      final productJson =
          (mockResponse['data'] as List)[0] as Map<String, dynamic>;
      final product = Product.fromJson(productJson);

      expect(product.id, '1244');
      expect(product.name, 'V 60 Cold');
      expect(product.price, 10.0);
      expect(product.category, 'قهوة');
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

      expect(category.id, '5');
      expect(category.name, 'قهوة');
      expect(category.type, 'meals');
      expect(category.parentId, null);
    });
  });
}
