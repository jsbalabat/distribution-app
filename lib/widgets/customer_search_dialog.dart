import 'package:flutter/material.dart';
import '../styles/app_styles.dart';

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
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    filteredCustomers = [...widget.customers];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width > 600 ? 500.0 : screenSize.width * 0.9;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppStyles.borderRadiusLarge),
      ),
      elevation: AppStyles.modalElevation,
      child: Container(
        width: dialogWidth,
        constraints: const BoxConstraints(maxHeight: 600),
        decoration: BoxDecoration(
          color: AppStyles.cardColor,
          borderRadius: BorderRadius.circular(AppStyles.borderRadiusLarge),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppStyles.primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppStyles.borderRadiusLarge),
                  topRight: Radius.circular(AppStyles.borderRadiusLarge),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(
                        AppStyles.borderRadiusSmall,
                      ),
                    ),
                    child: const Icon(
                      Icons.people_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Customer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Search and choose a customer',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Search Field
            Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration:
                    AppStyles.inputDecorationWithHint(
                      hintText: 'Search by customer name...',
                      prefixIcon: Icons.search_rounded,
                    ).copyWith(
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  query = '';
                                  filteredCustomers = [...widget.customers];
                                });
                              },
                            )
                          : null,
                    ),
                onChanged: (value) {
                  setState(() {
                    query = value.toLowerCase();
                    filteredCustomers = widget.customers
                        .where(
                          (customer) =>
                              customer['name'].toLowerCase().contains(query) ||
                              customer['accountNumber'].toString().contains(
                                query,
                              ),
                        )
                        .toList();
                  });
                },
              ),
            ),

            // Results Count
            if (query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  '${filteredCustomers.length} customer${filteredCustomers.length != 1 ? 's' : ''} found',
                  style: AppStyles.captionStyle.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            // Customer List
            Flexible(
              child: filteredCustomers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 64,
                              color: AppStyles.textLightColor,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              query.isEmpty
                                  ? 'No customers available'
                                  : 'No customers found',
                              style: AppStyles.bodyStyle.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              query.isEmpty
                                  ? 'Add customers to get started'
                                  : 'Try a different search term',
                              style: AppStyles.captionStyle,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: filteredCustomers.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final customer = filteredCustomers[index];
                        return InkWell(
                          onTap: () {
                            widget.onCustomerSelected(customer);
                            Navigator.pop(context);
                          },
                          borderRadius: BorderRadius.circular(
                            AppStyles.borderRadiusMedium,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppStyles.backgroundColor,
                              borderRadius: BorderRadius.circular(
                                AppStyles.borderRadiusMedium,
                              ),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.08),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppStyles.primaryColor.withValues(
                                      alpha: 0.05,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppStyles.borderRadiusSmall,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.person_rounded,
                                    color: AppStyles.primaryColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customer['name'],
                                        style: AppStyles.bodyStyle.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.numbers_rounded,
                                            size: 14,
                                            color: AppStyles.textSecondaryColor,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Account: ${customer['accountNumber']}',
                                            style: AppStyles.captionStyle
                                                .copyWith(fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 16,
                                  color: AppStyles.textLightColor,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
