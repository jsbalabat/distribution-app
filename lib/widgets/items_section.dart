import 'package:flutter/material.dart';
import '../models/item_model.dart';
import './item_selector.dart';

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
  // final String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    double total = widget.selectedItems.fold(
      0.0,
      (currentTotal, item) => currentTotal + (item['subtotal'] ?? 0.0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 500,
          child: RefreshIndicator(
            onRefresh: widget.onRefresh ?? () async {},
            child: _buildItemsList(),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Selected Items:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),

        // This is where selectedItems is used - line 58 in your error
        ...widget.selectedItems.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.withValues(alpha: 0.1),
                child: Text(
                  item['code']?.substring(0, 2).toUpperCase() ?? 'IT',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              // Item code as title
              title: Text(
                item['code'] ?? item['name'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              // Item name and details in subtitle
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'] ?? '',
                    style: const TextStyle(fontSize: 14),
                  ),
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
                    onPressed: () => widget.onEditQuantity(index),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => widget.onDeleteItem(index),
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
    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.loadError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error loading items: ${widget.loadError}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: widget.onRefresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (widget.allItems.isEmpty) {
      return const Center(child: Text('No items found.'));
    }

    return ItemSelector(
      items: widget.allItems,
      onItemSelected: widget.onItemSelected,
    );
  }
}
