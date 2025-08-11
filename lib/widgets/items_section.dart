import 'package:flutter/material.dart';
import '../models/item_model.dart';
import '../services/firestore_service.dart';
import './item_selector.dart';

class ItemsSection extends StatelessWidget {
  final List<Item> allItems;
  final List<Map<String, dynamic>> selectedItems;
  final Function(Item) onItemSelected;
  final Function(int) onEditQuantity;
  final Function(int) onDeleteItem;

  const ItemsSection({
    super.key,
    required this.allItems,
    required this.selectedItems,
    required this.onItemSelected,
    required this.onEditQuantity,
    required this.onDeleteItem,
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
          child: FutureBuilder<List<Item>>(
            future: FirestoreService().fetchItems(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return const Text('Error loading items');
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Text('No items found.');
              }

              return ItemSelector(
                items: snapshot.data!,
                onItemSelected: onItemSelected,
              );
            },
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
              title: Text(item['name']),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
