import 'package:flutter/material.dart';
import '../models/item_model.dart';

class QuantityInputDialog extends StatefulWidget {
  final Item item;
  final double autoPrice;
  final Function(int quantity) onAdd;

  const QuantityInputDialog({
    super.key,
    required this.item,
    required this.autoPrice,
    required this.onAdd,
  });

  @override
  State<QuantityInputDialog> createState() => _QuantityInputDialogState();
}

class _QuantityInputDialogState extends State<QuantityInputDialog> {
  final TextEditingController qtyController = TextEditingController();

  @override
  void dispose() {
    qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add ${widget.item.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: qtyController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantity'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final qty = int.tryParse(qtyController.text) ?? 0;

            if (qty <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Quantity must be greater than 0'),
                ),
              );
              return;
            } else if (qty > widget.item.stock) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Quantity cannot exceed available stock (Stock: ${widget.item.stock}).',
                  ),
                ),
              );
              return;
            }

            widget.onAdd(qty);
            Navigator.pop(context);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
