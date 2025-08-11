import 'package:flutter/material.dart';

class ReviewSection extends StatelessWidget {
  final double totalAmount;
  final String? sorNumber;
  final String? accountNumber;
  final String? remark1;
  final String? remark2;

  const ReviewSection({
    super.key,
    required this.totalAmount,
    this.sorNumber,
    this.accountNumber,
    this.remark1,
    this.remark2,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Total: ₱${totalAmount.toStringAsFixed(2)}'),
        const SizedBox(height: 10),
        if (sorNumber != null) Text('SOR #: $sorNumber'),
        if (accountNumber != null) Text('Account #: $accountNumber'),
        if (remark1 != null)
          Text('Remark 1: $remark1', style: const TextStyle(color: Colors.red)),
        if (remark2 != null)
          Text('Remark 2: $remark2', style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 20),
      ],
    );
  }
}
