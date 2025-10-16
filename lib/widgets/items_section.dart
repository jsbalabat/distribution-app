import 'package:flutter/material.dart';
import '../models/item_model.dart';
import './item_selector.dart';

class ItemsSection extends StatelessWidget {
  final List<Item> allItems;
  final List<Map<String, dynamic>> selectedItems;
  final Function(Item) onItemSelected;
  final Function(int) onEditQuantity;
  final Function(int) onDeleteItem;
  final Future<void> Function() onRefresh;
  final bool isLoading;
  final String? loadError;

  const ItemsSection({
    super.key,
    required this.allItems,
    required this.selectedItems,
    required this.onItemSelected,
    required this.onEditQuantity,
    required this.onDeleteItem,
    required this.onRefresh,
    required this.isLoading,
    this.loadError,
  });

  @override
  Widget build(BuildContext context) {
    double total = selectedItems.fold(
      0.0,
      (currentTotal, item) => currentTotal + (item['subtotal'] ?? 0.0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 500,
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: _buildItemsList(),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Selected Items:',
          style: TextStyle(fontWeight: FontWeight.bold),
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

  Widget _buildItemsList() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (loadError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error loading items: $loadError'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRefresh, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (allItems.isEmpty) {
      return const Center(child: Text('No items found.'));
    }

    return ItemSelector(items: allItems, onItemSelected: onItemSelected);
  }
}
