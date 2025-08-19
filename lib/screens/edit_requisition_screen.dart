import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/edit_quantity_dialog.dart';
import '../widgets/confirmation_dialog.dart';
import '../models/item_model.dart';
import '../services/firestore_service.dart';
import '../widgets/quantity_input_dialog.dart';
import '../styles/app_styles.dart';

class EditRequisitionScreen extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> formData;

  const EditRequisitionScreen({
    super.key,
    required this.docId,
    required this.formData,
  });

  @override
  State<EditRequisitionScreen> createState() => _EditRequisitionScreenState();
}

class _EditRequisitionScreenState extends State<EditRequisitionScreen> {
  // Color scheme to match other screens

  List<Map<String, dynamic>> _items = [];
  DateTime? _invoiceDate;
  DateTime? _dispatchDate;
  bool _isLoading = false;
  bool _hasChanges = false;

  // For adding new items
  List<Item> _availableItems = [];
  bool _isLoadingAvailableItems = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _loadAvailableItems();
  }

  void _initializeData() {
    // Deep copy the items list to avoid modifying the original data
    _items =
        (widget.formData['items'] as List<dynamic>?)
            ?.map((item) => Map<String, dynamic>.from(item as Map))
            .toList() ??
        [];

    // Convert Firestore timestamps to DateTime
    if (widget.formData['invoiceDate'] is Timestamp) {
      _invoiceDate = (widget.formData['invoiceDate'] as Timestamp).toDate();
    }

    if (widget.formData['dispatchDate'] is Timestamp) {
      _dispatchDate = (widget.formData['dispatchDate'] as Timestamp).toDate();
    }
  }

  // Load available items from Firestore
  Future<void> _loadAvailableItems() async {
    setState(() {
      _isLoadingAvailableItems = true;
    });

    try {
      final items = await FirestoreService().fetchItems();

      if (mounted) {
        setState(() {
          _availableItems = items;
          _isLoadingAvailableItems = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load available items: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(10),
          ),
        );
        setState(() {
          _isLoadingAvailableItems = false;
        });
      }
    }
  }

  double _calculateTotal() {
    return _items.fold(0.0, (total, item) {
      final subtotal = item['subtotal'];
      return total + (subtotal is num ? subtotal.toDouble() : 0.0);
    });
  }

  void _editItemQuantity(int index) {
    final currentItem = _items[index];
    final currentQuantity = currentItem['quantity'] as int? ?? 0;

    showDialog(
      context: context,
      builder: (context) => EditQuantityDialog(
        itemName: currentItem['name'],
        currentQuantity: currentQuantity,
        onUpdate: (newQty) {
          setState(() {
            _items[index]['quantity'] = newQty;
            _items[index]['subtotal'] = newQty * currentItem['unitPrice'];
            _hasChanges = true;
          });
        },
      ),
    );
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _hasChanges = true;
    });
  }

  // Show item selection dialog
  void _showAddItemDialog() {
    List<Item> filteredItems = List.from(_availableItems);
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Add New Item',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppStyles.textColor,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    // Search bar
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by name or code',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppStyles.primaryColor,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                          isDense: true,
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: AppStyles.subtitleColor,
                                  ),
                                  onPressed: () {
                                    setDialogState(() {
                                      searchQuery = '';
                                      filteredItems = List.from(
                                        _availableItems,
                                      );
                                    });
                                  },
                                )
                              : null,
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            searchQuery = value;
                            if (value.isEmpty) {
                              filteredItems = List.from(_availableItems);
                            } else {
                              filteredItems = _availableItems
                                  .where(
                                    (item) =>
                                        item.name.toLowerCase().contains(
                                          value.toLowerCase(),
                                        ) ||
                                        item.code.toLowerCase().contains(
                                          value.toLowerCase(),
                                        ),
                                  )
                                  .toList();
                            }
                          });
                        },
                      ),
                    ),

                    // Item list
                    Expanded(
                      child: _isLoadingAvailableItems
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: AppStyles.primaryColor,
                              ),
                            )
                          : filteredItems.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_off,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No items found',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                final isAlreadyAdded = _items.any(
                                  (existingItem) =>
                                      existingItem['id'] == item.id,
                                );

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  color: isAlreadyAdded || item.stock <= 0
                                      ? Colors.grey[100]
                                      : AppStyles.cardColor,
                                  elevation: 0,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: AppStyles.primaryColor
                                          .withValues(alpha: 0.1),
                                      child: Text(
                                        item.name.substring(0, 1).toUpperCase(),
                                        style: const TextStyle(
                                          color: AppStyles.primaryColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      item.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: isAlreadyAdded || item.stock <= 0
                                            ? Colors.grey[600]
                                            : AppStyles.textColor,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Code: ${item.code} | Stock: ${item.stock}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isAlreadyAdded || item.stock <= 0
                                            ? Colors.grey[500]
                                            : AppStyles.subtitleColor,
                                      ),
                                    ),
                                    enabled: !isAlreadyAdded && item.stock > 0,
                                    onTap: isAlreadyAdded || item.stock <= 0
                                        ? null
                                        : () {
                                            Navigator.of(dialogContext).pop();
                                            _showQuantityInputDialog(item);
                                          },
                                    trailing: isAlreadyAdded
                                        ? Chip(
                                            label: const Text(
                                              'Added',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.white,
                                              ),
                                            ),
                                            backgroundColor: Colors.grey[600],
                                            padding: EdgeInsets.zero,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                          )
                                        : item.stock <= 0
                                        ? const Chip(
                                            label: Text(
                                              'Out of Stock',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.white,
                                              ),
                                            ),
                                            backgroundColor: Colors.red,
                                            padding: EdgeInsets.zero,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                          )
                                        : null,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppStyles.primaryColor,
                  ),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoadingAvailableItems
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                          _loadAvailableItems();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppStyles.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh Items'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Show quantity input dialog for new item
  void _showQuantityInputDialog(Item item) async {
    // Get price for customer's price level
    final priceLevel = widget.formData['priceLevel'] ?? 'regularPrice';

    try {
      final itemData = await FirestoreService().fetchItemPrice(item.code);

      if (!mounted) return;

      if (itemData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to get item price'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final priceLevelMap = {
        'specialODPrice': 'specialOD',
        'rmlInclusivePrice': 'rmlInclusivePrice',
        'regularPrice': 'regularPrice',
      };

      final firestorePriceKey = priceLevelMap[priceLevel] ?? 'regularPrice';
      final autoPrice = (itemData[firestorePriceKey] ?? 0).toDouble();

      showDialog(
        context: context,
        builder: (context) => QuantityInputDialog(
          item: item,
          autoPrice: autoPrice,
          onAdd: (qty) {
            // Add to items list
            setState(() {
              final data = {
                'id': item.id,
                'name': item.name,
                'code': item.code,
                'quantity': qty,
                'unitPrice': autoPrice,
                'subtotal': qty * autoPrice,
              };
              _items.add(data);
              _hasChanges = true;
            });
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching item price: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _selectDate(BuildContext context, bool isInvoiceDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isInvoiceDate
          ? _invoiceDate ?? DateTime.now()
          : _dispatchDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppStyles.primaryColor,
              onPrimary: Colors.white,
              surface: AppStyles.cardColor,
              onSurface: AppStyles.textColor,
            ),
            dialogBackgroundColor: AppStyles.cardColor,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isInvoiceDate) {
          _invoiceDate = picked;
        } else {
          _dispatchDate = picked;
        }
        _hasChanges = true;
      });
    }
  }

  Future<void> _saveChanges() async {
    // Show confirmation dialog first
    showDialog(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Save Changes',
        message: 'Are you sure you want to save these changes?',
        onConfirm: () async {
          Navigator.pop(context); // Close dialog

          setState(() {
            _isLoading = true;
          });

          try {
            // Update the data in Firestore
            await FirebaseFirestore.instance
                .collection('salesRequisitions')
                .doc(widget.docId)
                .update({
                  'items': _items,
                  'totalAmount': _calculateTotal(),
                  'invoiceDate': _invoiceDate,
                  'dispatchDate': _dispatchDate,
                  'lastEdited': Timestamp.now(),
                });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Changes saved successfully'),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
              );
              Navigator.pop(context); // Return to dashboard
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error saving changes: $e'),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
              );
            }
          } finally {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          }
        },
      ),
    );
  }

  // Show confirmation for cancel
  void _confirmCancel() {
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }

    showDialog(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Discard Changes',
        message:
            'You have unsaved changes. Are you sure you want to discard them?',
        onConfirm: () {
          Navigator.pop(context); // Close dialog
          Navigator.pop(context); // Return to dashboard
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final currencyFormat = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Edit Requisition',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppStyles.primaryColor,
        elevation: 0,
        actions: [
          if (_hasChanges)
            IconButton(
              icon: const Icon(Icons.save, color: Colors.white),
              onPressed: _isLoading ? null : _saveChanges,
              tooltip: 'Save Changes',
            ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _confirmCancel,
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppStyles.primaryColor),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer information (readonly)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppStyles.primaryColor.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.person,
                                  color: AppStyles.primaryColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.formData['customerName'] ??
                                          'Unknown Customer',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppStyles.textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'SOR #: ${widget.formData['sorNumber'] ?? ''}',
                                      style: const TextStyle(
                                        color: AppStyles.subtitleColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Account Number',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppStyles.subtitleColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.formData['accountNumber'] ?? 'N/A',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Area',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppStyles.subtitleColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.formData['area'] ?? 'N/A',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Dates (editable)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppStyles.primaryColor.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.calendar_today,
                                  color: AppStyles.primaryColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Dates',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppStyles.textColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Invoice Date
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Invoice Date',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _selectDate(context, true),
                                  icon: const Icon(
                                    Icons.edit_calendar,
                                    size: 16,
                                    color: AppStyles.primaryColor,
                                  ),
                                  label: Text(
                                    _invoiceDate != null
                                        ? dateFormat.format(_invoiceDate!)
                                        : 'Select Date',
                                    style: const TextStyle(
                                      color: AppStyles.primaryColor,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    backgroundColor: AppStyles.primaryColor
                                        .withValues(alpha: 0.1),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Dispatch Date
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Dispatch Date',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _selectDate(context, false),
                                  icon: const Icon(
                                    Icons.edit_calendar,
                                    size: 16,
                                    color: AppStyles.primaryColor,
                                  ),
                                  label: Text(
                                    _dispatchDate != null
                                        ? dateFormat.format(_dispatchDate!)
                                        : 'Select Date',
                                    style: const TextStyle(
                                      color: AppStyles.primaryColor,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    backgroundColor: AppStyles.primaryColor
                                        .withValues(alpha: 0.1),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Items (editable)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppStyles.primaryColor.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.shopping_cart,
                                  color: AppStyles.primaryColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Items',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppStyles.textColor,
                                  ),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _showAddItemDialog,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add Item'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppStyles.secondaryColor,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Item list
                          _items.isEmpty
                              ? Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.grey[200]!,
                                    ),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.shopping_basket,
                                          size: 48,
                                          color: Colors.grey[400],
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'No items in this order',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: AppStyles.subtitleColor,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Add items using the button above',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _items.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final item = _items[index];
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: index.isOdd
                                            ? Colors.grey[50]
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 4,
                                            ),
                                        leading: CircleAvatar(
                                          backgroundColor: AppStyles
                                              .primaryColor
                                              .withValues(alpha: 0.1),
                                          child: Text(
                                            '${item['quantity']}',
                                            style: const TextStyle(
                                              color: AppStyles.primaryColor,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          item['name'] ?? 'Unknown Item',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        subtitle: Wrap(
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              currencyFormat.format(
                                                item['unitPrice'],
                                              ),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                            const Text(
                                              ' × ',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppStyles.subtitleColor,
                                              ),
                                            ),
                                            Text(
                                              '${item['quantity']}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                            const Text(
                                              ' = ',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppStyles.subtitleColor,
                                              ),
                                            ),
                                            Text(
                                              currencyFormat.format(
                                                item['subtotal'],
                                              ),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: AppStyles.primaryColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                Icons.edit,
                                                color: AppStyles.primaryColor,
                                                size: 20,
                                              ),
                                              onPressed: () =>
                                                  _editItemQuantity(index),
                                              tooltip: 'Edit Quantity',
                                              style: IconButton.styleFrom(
                                                backgroundColor: AppStyles
                                                    .primaryColor
                                                    .withValues(alpha: 0.1),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete,
                                                color: AppStyles.secondaryColor,
                                                size: 20,
                                              ),
                                              onPressed: () =>
                                                  _removeItem(index),
                                              tooltip: 'Remove Item',
                                              style: IconButton.styleFrom(
                                                backgroundColor: AppStyles
                                                    .secondaryColor
                                                    .withValues(alpha: 0.1),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),

                          if (_items.isNotEmpty) ...[
                            const Divider(height: 32),

                            // Total
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppStyles.primaryColor.withValues(
                                  alpha: 0.05,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total Amount:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    currencyFormat.format(_calculateTotal()),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: AppStyles.primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _confirmCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppStyles.secondaryColor,
                      side: const BorderSide(color: AppStyles.secondaryColor),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading || !_hasChanges ? null : _saveChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppStyles.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      disabledBackgroundColor: Colors.grey[300],
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isLoading ? 'Saving...' : 'Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
