import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../styles/app_styles.dart';
import '../utils/requisition_fields.dart';

class ViewReportsScreen extends StatelessWidget {
  const ViewReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return Scaffold(
      backgroundColor: AppStyles.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Analytics & Reports',
          style: AppStyles.appBarTitleStyle,
        ),
        backgroundColor: AppStyles.adminPrimaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestoreService.getAllSubmissionsStream(limit: 500),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(child: Text('No sales data available.'));
          }

          // --- Perform Calculations ---
          double totalSales = 0;
          int totalOrders = docs.length;
          final Map<String, double> productSales = {};
          final Map<String, int> productQuantities = {};

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;

            // Total Sales
            final amount = RequisitionFields.totalAmount(data);
            totalSales += amount;

            // Product Stats
            if (data['items'] != null) {
              final items = data['items'] as List<dynamic>;
              for (var item in items) {
                final name = item['name'] as String? ?? 'Unknown';
                final qty = (item['quantity'] as num?)?.toInt() ?? 0;
                final unitPrice =
                    (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
                final subtotal =
                    (item['subtotal'] as num?)?.toDouble() ?? (qty * unitPrice);

                productSales[name] = (productSales[name] ?? 0) + subtotal;
                productQuantities[name] = (productQuantities[name] ?? 0) + qty;
              }
            }
          }

          // Top Products (by Sales Amount)
          final topProducts = productSales.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)); // Descending
          final top5Products = topProducts.take(5).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppStyles.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Summary Cards
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppStyles.spacingM,
                  mainAxisSpacing: AppStyles.spacingM,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.5,
                  children: [
                    _buildSummaryCard(
                      title: 'Total Revenue',
                      value: currencyFormat.format(totalSales),
                      icon: Icons.attach_money,
                      color: AppStyles.successColor,
                    ),
                    _buildSummaryCard(
                      title: 'Total Orders',
                      value: totalOrders.toString(),
                      icon: Icons.shopping_bag_outlined,
                      color: Colors.blueGrey,
                    ),
                    _buildSummaryCard(
                      title: 'Avg. Order Value',
                      value: totalOrders > 0
                          ? currencyFormat.format(totalSales / totalOrders)
                          : '₱0.00',
                      icon: Icons.analytics_outlined,
                      color: Colors.orange[800]!,
                    ),
                    _buildSummaryCard(
                      title: 'Unique Products',
                      value: productSales.length.toString(),
                      icon: Icons.inventory_2_outlined,
                      color: Colors.teal,
                    ),
                  ],
                ),

                const SizedBox(height: AppStyles.spacingXL),

                // 2. Top Selling Products
                Text('Top Performing Products', style: AppStyles.headingStyle),
                const SizedBox(height: AppStyles.spacingM),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppStyles.borderRadiusMedium,
                    ),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: top5Products.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final product = top5Products[index];
                      final name = product.key;
                      final sales = product.value;
                      final qty = productQuantities[name] ?? 0;

                      // Calculate progress based on highest selling item
                      final double maxSales = top5Products.first.value;
                      final double progress = maxSales > 0
                          ? sales / maxSales
                          : 0;

                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  currencyFormat.format(sales),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '$qty units sold',
                                  style: AppStyles.captionStyle,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppStyles.adminPrimaryColor.withValues(
                                  alpha: 0.7 + (progress * 0.3),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(4),
                              minHeight: 6,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: AppStyles.spacingXL),

                // 3. Recent Transactions
                Text('Recent Transactions', style: AppStyles.headingStyle),
                const SizedBox(height: AppStyles.spacingM),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.take(10).length, // Show last 10
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final date =
                        RequisitionFields.timestamp(data) ?? DateTime.now();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.grey[200],
                          child: const Icon(
                            Icons.receipt_long,
                            color: Colors.black87,
                          ),
                        ),
                        title: Text(
                          data['customerName'] ?? 'Unknown Customer',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${RequisitionFields.sorNumber(data)} • ${DateFormat.yMMMd().format(date)}',
                          style: AppStyles.captionStyle,
                        ),
                        trailing: Text(
                          currencyFormat.format(
                            RequisitionFields.totalAmount(data),
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppStyles.borderRadiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey[200]!),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppStyles.textColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
