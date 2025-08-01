class Item {
  final String id;
  final String name;
  final String code;
  final int stock;

  Item({
    required this.id,
    required this.name,
    required this.stock,
    required this.code,
  });

  factory Item.fromMap(String id, Map<String, dynamic> data) {
    return Item(
      id: id,
      name: data['description'] ?? 'Unknown Item',
      stock: data['quantity'] != null ? data['quantity'] as int : 0,
      code: data['itemCode'] ?? 'Unknown Code',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'stock': stock,
      'code': code,
    };
  }

  // For debugging only
  // @override
  // String toString() {
  //   return 'Item(id: $id, name: $name, stock: $stock)';
  // }
}