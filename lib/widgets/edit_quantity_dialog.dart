import 'package:flutter/material.dart';

class EditQuantityDialog extends StatefulWidget {
  final String itemName;
  final int currentQuantity;
  final Function(int newQuantity) onUpdate;

  const EditQuantityDialog({
    super.key,
    required this.itemName,
    required this.currentQuantity,
    required this.onUpdate,
  });

  @override
  State<EditQuantityDialog> createState() => _EditQuantityDialogState();
}

class _EditQuantityDialogState extends State<EditQuantityDialog> {
  late final TextEditingController editController;

  @override
  void initState() {
    super.initState();
    editController = TextEditingController(
      text: widget.currentQuantity.toString(),
    );
  }

  @override
  void dispose() {
    editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Quantity: ${widget.itemName}'),
      content: TextField(
        controller: editController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'New Quantity'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final newQty = int.tryParse(editController.text) ?? 0;
            if (newQty <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Quantity must be greater than 0'),
                ),
              );
              return;
            }

            widget.onUpdate(newQty);
            Navigator.pop(context);
          },
          child: const Text('Update'),
        ),
      ],
    );
  }
}
