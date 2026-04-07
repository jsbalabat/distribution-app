class Item {
  final String id;
  final String name;
  final String code;
  final int stock;
  final String description;

  Item({
    required this.id,
    required this.name,
    required this.stock,
    required this.code,
    required this.description,
  });

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory Item.fromMap(String id, Map<String, dynamic> data) {
    final nameValue = (data['name'] ?? data['description'] ?? '').toString();
    final codeValue = (data['code'] ?? data['itemCode'] ?? '').toString();
    final stockValue = _toInt(data['stock'] ?? data['quantity']);

    return Item(
      id: id,
      name: nameValue.isNotEmpty ? nameValue : 'Unknown Item',
      stock: stockValue,
      code: codeValue.isNotEmpty ? codeValue : 'Unknown Code',
      description: (data['description'] ?? nameValue).toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      // Canonical fields used by UI and reports
      'name': name,
      'stock': stock,
      'code': code,
      'description': description,
      // Backward-compatible fields used in some collections/queries
      'itemCode': code,
      'quantity': stock,
    };
  }

  // For debugging only
  // @override
  // String toString() {
  //   return 'Item(id: $id, name: $name, stock: $stock)';
  // }
}
