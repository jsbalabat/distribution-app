import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/edit_quantity_dialog.dart';
import '../widgets/confirmation_dialog.dart';
import '../models/item_model.dart';
import '../services/firestore_service.dart';
import '../widgets/quantity_input_dialog.dart';

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
          SnackBar(content: Text('Failed to load available items: $e')),
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
    // Don't create a controller here - create it inside the builder
    List<Item> filteredItems = List.from(_availableItems);
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              title: const Text('Add New Item'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    // Search bar WITHOUT TextEditingController
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: TextField(
                        // Don't use initialValue and controller at the same time
                        // Remove both of these lines:
                        // controller: null,
                        // initialValue: null,

                        // Keep the rest of your TextField properties
                        decoration: InputDecoration(
                          hintText: 'Search by name or code',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                          ),
                          isDense: true,
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
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

                    // Item list - no changes needed here
                    Expanded(
                      child: _isLoadingAvailableItems
                          ? const Center(child: CircularProgressIndicator())
                          : filteredItems.isEmpty
                          ? const Center(child: Text('No items found'))
                          : ListView.builder(
                              itemCount: filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                final isAlreadyAdded = _items.any(
                                  (existingItem) =>
                                      existingItem['id'] == item.id,
                                );

                                return ListTile(
                                  title: Text(item.name),
                                  subtitle: Text(
                                    'Code: ${item.code} | Stock: ${item.stock}',
                                  ),
                                  enabled: !isAlreadyAdded && item.stock > 0,
                                  onTap: isAlreadyAdded || item.stock <= 0
                                      ? null
                                      : () {
                                          Navigator.of(dialogContext).pop();
                                          _showQuantityInputDialog(item);
                                        },
                                  trailing: isAlreadyAdded
                                      ? const Chip(
                                          label: Text('Already Added'),
                                          backgroundColor: Colors.grey,
                                        )
                                      : item.stock <= 0
                                      ? const Chip(
                                          label: Text('Out of Stock'),
                                          backgroundColor: Colors.red,
                                        )
                                      : null,
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
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: _isLoadingAvailableItems
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                          _loadAvailableItems();
                        },
                  child: const Text('Refresh Items'),
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
          const SnackBar(content: Text('Failed to get item price')),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error fetching item price: $e')));
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
                const SnackBar(content: Text('Changes saved successfully')),
              );
              Navigator.pop(context); // Return to dashboard
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error saving changes: $e')),
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
    final dateFormat = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Requisition'),
        actions: [
          if (_hasChanges)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isLoading ? null : _saveChanges,
              tooltip: 'Save Changes',
            ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _confirmCancel,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer information (readonly)
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.formData['customerName'] ??
                                'Unknown Customer',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('SOR #: ${widget.formData['sorNumber'] ?? ''}'),
                          Text(
                            'Account #: ${widget.formData['accountNumber'] ?? ''}',
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Dates (editable)
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Dates',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Invoice Date
                          Row(
                            children: [
                              const Text('Invoice Date: '),
                              TextButton(
                                onPressed: () => _selectDate(context, true),
                                child: Text(
                                  _invoiceDate != null
                                      ? dateFormat.format(_invoiceDate!)
                                      : 'Select Date',
                                ),
                              ),
                            ],
                          ),

                          // Dispatch Date
                          Row(
                            children: [
                              const Text('Dispatch Date: '),
                              TextButton(
                                onPressed: () => _selectDate(context, false),
                                child: Text(
                                  _dispatchDate != null
                                      ? dateFormat.format(_dispatchDate!)
                                      : 'Select Date',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Items (editable)
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Items',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _showAddItemDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Item'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Item list
                          _items.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Text(
                                      'No items in this order. Add items using the button above.',
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _items.length,
                                  itemBuilder: (context, index) {
                                    final item = _items[index];
                                    return ListTile(
                                      title: Text(
                                        item['name'] ?? 'Unknown Item',
                                      ),
                                      subtitle: Text(
                                        'Qty: ${item['quantity']} @ ₱${item['unitPrice']?.toStringAsFixed(2) ?? '0.00'} = ₱${item['subtotal']?.toStringAsFixed(2) ?? '0.00'}',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            onPressed: () =>
                                                _editItemQuantity(index),
                                            tooltip: 'Edit Quantity',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete),
                                            onPressed: () => _removeItem(index),
                                            tooltip: 'Remove Item',
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                          const Divider(),

                          // Total
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'Total Amount: ₱${_calculateTotal().toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _confirmCancel,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoading || !_hasChanges ? null : _saveChanges,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
