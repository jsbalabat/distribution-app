import 'package:flutter/material.dart';

class CustomerSearchDialog extends StatefulWidget {
  final List<Map<String, dynamic>> customers;
  final Function(Map<String, dynamic> customer) onCustomerSelected;

  const CustomerSearchDialog({
    super.key,
    required this.customers,
    required this.onCustomerSelected,
  });

  @override
  State<CustomerSearchDialog> createState() => _CustomerSearchDialogState();
}

class _CustomerSearchDialogState extends State<CustomerSearchDialog> {
  String query = '';
  late List<Map<String, dynamic>> filteredCustomers;

  @override
  void initState() {
    super.initState();
    filteredCustomers = [...widget.customers];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Customer'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(hintText: 'Search customer'),
              onChanged: (value) {
                query = value.toLowerCase();
                setState(() {
                  filteredCustomers = widget.customers
                      .where(
                        (customer) =>
                            customer['name'].toLowerCase().contains(query),
                      )
                      .toList();
                });
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 300,
              width: 300,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filteredCustomers.length,
                itemBuilder: (context, index) {
                  final customer = filteredCustomers[index];
                  return ListTile(
                    title: Text(customer['name']),
                    subtitle: Text('Acct #: ${customer['accountNumber']}'),
                    onTap: () {
                      widget.onCustomerSelected(customer);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
