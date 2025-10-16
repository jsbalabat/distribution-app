import 'package:flutter/material.dart';
import '../models/item_model.dart';

class ItemSelector extends StatelessWidget {
  final List<Item> items;
  final Function(Item) onItemSelected;

  const ItemSelector({
    super.key,
    required this.items,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    TextEditingController searchController = TextEditingController();
    List<Item> filteredItems = List.from(items);

    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          children: [
            TextField(
              controller: searchController,
              decoration: const InputDecoration(labelText: 'Search items'),
              onChanged: (value) {
                setState(() {
                  filteredItems = items
                      .where(
                        (item) => item.code.toLowerCase().contains(
                          value.toLowerCase(),
                        ),
                      )
                      .toList();
                });
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filteredItems.length,
                itemBuilder: (_, index) {
                  final item = filteredItems[index];
                  return ListTile(
                    title: Text(item.code),
                    subtitle: Text(item.name),
                    trailing: Text('Stock: ${item.stock}'),
                    onTap: () => onItemSelected(item),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
