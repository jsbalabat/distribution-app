import 'package:flutter_test/flutter_test.dart';
import 'package:new_test_store/models/item_model.dart';

void main() {
  group('Item', () {
    test('maps legacy inventory fields into canonical model fields', () {
      final item = Item.fromMap('item-1', {
        'description': 'Filtered Water',
        'itemCode': 'WTR-01',
        'quantity': 48,
      });

      expect(item.id, 'item-1');
      expect(item.name, 'Filtered Water');
      expect(item.code, 'WTR-01');
      expect(item.stock, 48);
      expect(item.description, 'Filtered Water');
    });

    test('provides backward-compatible map keys', () {
      final item = Item(
        id: 'item-2',
        name: 'Notebook',
        stock: 12,
        code: 'NB-12',
        description: 'A5 notebook',
      );

      final map = item.toMap();

      expect(map['name'], 'Notebook');
      expect(map['stock'], 12);
      expect(map['code'], 'NB-12');
      expect(map['description'], 'A5 notebook');
      expect(map['itemCode'], 'NB-12');
      expect(map['quantity'], 12);
    });
  });
}
