import 'package:flutter/material.dart';
import '../models/item_model.dart';

class ItemsSection extends StatefulWidget {
  final bool isLoading;
  final String? loadError;
  final List<Item> allItems;
  final List<Map<String, dynamic>> selectedItems;
  final Function(Item) onItemSelected;
  final Function(int) onEditQuantity;
  final Function(int) onDeleteItem;
  final Future<void> Function()? onRefresh;

  const ItemsSection({
    super.key,
    required this.isLoading,
    required this.loadError,
    required this.allItems,
    required this.selectedItems,
    required this.onItemSelected,
    required this.onEditQuantity,
    required this.onDeleteItem,
    this.onRefresh,
  });

  @override
  State<ItemsSection> createState() => _ItemsSectionState();
}

class _ItemsSectionState extends State<ItemsSection> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filteredItems = widget.allItems
        .where(
          (item) =>
              item.code.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search by Item Code',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
        ),
        const SizedBox(height: 6),

        ...selectedItems.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;

          return Card(
            child: ListTile(
              // Changed: Item code as title
              title: Text(
                item['code'] ??
                    item['name'], // Fallback to name if code doesn't exist
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              // Changed: Item name and other details in subtitle
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['name'], style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Qty: ${item['quantity']}'),
                  Text('Unit Price: ₱${item['unitPrice'].toStringAsFixed(2)}'),
                  Text('Subtotal: ₱${item['subtotal'].toStringAsFixed(2)}'),
                ],
              ),
              trailing: Wrap(
                spacing: 12,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => onEditQuantity(index),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => onDeleteItem(index),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
        Text(
          'Total: ₱${total.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }
}
