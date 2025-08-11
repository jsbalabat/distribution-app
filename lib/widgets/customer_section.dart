import 'package:flutter/material.dart';

class CustomerSection extends StatelessWidget {
  final Map<String, dynamic>? selectedCustomer;
  final VoidCallback onTap;

  const CustomerSection({
    super.key,
    required this.selectedCustomer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer Info',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Customer',
              border: OutlineInputBorder(),
            ),
            child: Text(
              selectedCustomer?['name'] ?? 'Select a customer',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        if (selectedCustomer?['area'] != null)
          Text('Area: ${selectedCustomer?['area']}'),
        if (selectedCustomer?['paymentTerms'] != null)
          Text('Terms: ${selectedCustomer?['paymentTerms']}'),
      ],
    );
  }
}
