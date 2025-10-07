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
        const SizedBox(height: 12),
        widget.isLoading
            ? const Center(child: CircularProgressIndicator())
            : widget.loadError != null
            ? Center(child: Text(widget.loadError!))
            : SizedBox(
                height: 300, // Set a fixed height for the list
                child: ListView.builder(
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return ListTile(
                      title: Text(item.code), // Item code as main entry
                      subtitle: Text(
                        item.description,
                      ), // Description as subtitle
                      trailing: Text('Stock: ${item.stock}'),
                      onTap: () => widget.onItemSelected(item),
                    );
                  },
                ),
              ),
      ],
    );
  }
}
