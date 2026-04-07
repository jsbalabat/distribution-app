import 'package:flutter/material.dart';
import '../models/item_model.dart';
import '../styles/app_styles.dart';

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
            // Modern Search Bar
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(
                  AppStyles.borderRadiusMedium,
                ),
                border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: searchController,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppStyles.textColor,
                  letterSpacing: 0.2,
                ),
                decoration: InputDecoration(
                  hintText: 'Search by item code or name...',
                  hintStyle: TextStyle(
                    color: AppStyles.textLightColor,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppStyles.primaryColor,
                    size: 22,
                  ),
                  suffixIcon: searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: AppStyles.textSecondaryColor,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              searchController.clear();
                              filteredItems = List.from(items);
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    if (value.isEmpty) {
                      filteredItems = List.from(items);
                    } else {
                      filteredItems = items.where((item) {
                        final query = value.toLowerCase();
                        return item.code.toLowerCase().contains(query) ||
                            item.name.toLowerCase().contains(query);
                      }).toList();
                    }
                  });
                },
              ),
            ),

            // Results count
            if (searchController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Row(
                  children: [
                    Text(
                      '${filteredItems.length} item${filteredItems.length != 1 ? 's' : ''} found',
                      style: TextStyle(
                        color: AppStyles.subtitleColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 12),

            // Items List
            Expanded(
              child: filteredItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: AppStyles.textLightColor,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No items found',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppStyles.subtitleColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try adjusting your search',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppStyles.textLightColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredItems.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (_, index) {
                        final item = filteredItems[index];
                        final isLowStock = item.stock <= 0;

                        return InkWell(
                          onTap: () => onItemSelected(item),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                // Item Icon
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppStyles.primaryColor.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      item.code.substring(0, 2).toUpperCase(),
                                      style: const TextStyle(
                                        color: AppStyles.primaryColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Item Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.code,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: AppStyles.textColor,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppStyles.subtitleColor,
                                          height: 1.3,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),

                                // Stock Badge
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isLowStock
                                            ? const Color(0xFFFFEBEE)
                                            : const Color(0xFFF5F5F5),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isLowStock
                                              ? const Color(0xFFFF5252)
                                              : const Color(0xFFE0E0E0),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        '${item.stock}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: isLowStock
                                              ? const Color(0xFFD32F2F)
                                              : AppStyles.textColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'in stock',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppStyles.textLightColor,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(width: 8),
                                Icon(
                                  Icons.add_circle_outline,
                                  color: AppStyles.primaryColor,
                                  size: 24,
                                ),
                              ],
                            ),
                          ),
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
