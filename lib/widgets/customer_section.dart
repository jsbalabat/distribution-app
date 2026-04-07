import 'package:flutter/material.dart';
import '../styles/app_styles.dart';

class CustomerSection extends StatelessWidget {
  final Map<String, dynamic>? selectedCustomer;
  final VoidCallback onTap;

  const CustomerSection({
    super.key,
    required this.selectedCustomer,
    required this.onTap,
  });

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppStyles.primaryColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16, color: AppStyles.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppStyles.captionStyle.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppStyles.bodyStyle.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomer = selectedCustomer != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with action button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppStyles.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(
                      AppStyles.borderRadiusSmall,
                    ),
                  ),
                  child: const Icon(
                    Icons.people_rounded,
                    color: AppStyles.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Customer Information',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppStyles.textColor,
                  ),
                ),
              ],
            ),
            if (hasCustomer)
              TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Change'),
                style: TextButton.styleFrom(
                  foregroundColor: AppStyles.primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Customer Selection Card
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppStyles.borderRadiusMedium),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hasCustomer
                  ? AppStyles.cardColor
                  : AppStyles.backgroundColor,
              borderRadius: BorderRadius.circular(AppStyles.borderRadiusMedium),
              border: Border.all(
                color: hasCustomer
                    ? AppStyles.primaryColor.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.1),
                width: hasCustomer ? 2 : 1,
              ),
            ),
            child: hasCustomer
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Customer Name Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF000000), Color(0xFF2D2D2D)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppStyles.borderRadiusSmall,
                              ),
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'SELECTED CUSTOMER',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppStyles.textSecondaryColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  selectedCustomer!['name'] ?? 'Unknown',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppStyles.textColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(height: 1),
                      ),

                      // Customer Details Grid
                      if (selectedCustomer!['accountNumber'] != null)
                        _buildInfoRow(
                          icon: Icons.numbers_rounded,
                          label: 'Account Number',
                          value: selectedCustomer!['accountNumber'].toString(),
                        ),

                      if (selectedCustomer!['area'] != null)
                        _buildInfoRow(
                          icon: Icons.location_on_rounded,
                          label: 'Area',
                          value: selectedCustomer!['area'].toString(),
                        ),

                      if (selectedCustomer!['paymentTerms'] != null)
                        _buildInfoRow(
                          icon: Icons.payment_rounded,
                          label: 'Payment Terms',
                          value: selectedCustomer!['paymentTerms'].toString(),
                        ),

                      if (selectedCustomer!['creditLimit'] != null)
                        _buildInfoRow(
                          icon: Icons.account_balance_wallet_rounded,
                          label: 'Credit Limit',
                          value:
                              '₱${(selectedCustomer!['creditLimit'] as num).toStringAsFixed(2)}',
                        ),

                      if (selectedCustomer!['priceLevel'] != null)
                        _buildInfoRow(
                          icon: Icons.local_offer_rounded,
                          label: 'Price Level',
                          value: selectedCustomer!['priceLevel'].toString(),
                        ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppStyles.primaryColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(
                            AppStyles.borderRadiusSmall,
                          ),
                        ),
                        child: const Icon(
                          Icons.person_add_rounded,
                          color: AppStyles.primaryColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select a Customer',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppStyles.textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap to choose from customer list',
                              style: AppStyles.captionStyle.copyWith(
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: AppStyles.textLightColor,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
