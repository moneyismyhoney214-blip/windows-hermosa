import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/models.dart'; // Import correctly

void main() {
  test('Parse products from JSON file', () async {
    final file = File('products_response.json');
    if (!await file.exists()) {
      print('products_response.json not found. Run test_products.dart first.');
      return;
    }

    final jsonString = await file.readAsString();
    final json = jsonDecode(jsonString);

    if (json['data'] is List) {
      final list = json['data'] as List;
      print('Parsing ${list.length} products using Product.fromJson...');

      for (var i = 0; i < list.length; i++) {
        final itemJson = list[i] as Map<String, dynamic>;
        try {
          final product = Product.fromJson(itemJson);
          print(
              '✅ Product ${product.id} (${product.name}): Price = ${product.price}');

          if (product.price == 0.0) {
            print('   ⚠️ Warning: Price is 0.0');
          }

          expect(product.price, isNotNull);
        } catch (e) {
          print('❌ Failed to parse Product at index $i: $e');
          fail('Failed to parse product: $e');
        }
      }
    }
  });
}
