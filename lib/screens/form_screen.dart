// import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import './../models/item_model.dart';
import './../widgets/item_selector.dart';

class FormScreen extends StatefulWidget {
  const FormScreen({super.key});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;

  // Example fields from the SOR form
  // final _companyCodeController = TextEditingController();
  final _sorNoController = TextEditingController();
  // final _customerNameController = TextEditingController(); // Not needed if using Dropdown
  final _deliveryInstructionController = TextEditingController();
  final _invoiceNumberController = TextEditingController();
  final _itemDescriptionController = TextEditingController();
  final _itemQuantityController = TextEditingController();

  String? _remark1;
  String? _remark2;
  String? _accountNumber;
  String? _sorNumber;
  String? _area;
  String? _paymentTerms;
  // String? _postalAddress;
  double? _creditLimit;
  double? _amountDue;
  double? _over30Days;
  double? _unsecuredFunds;

  Map<String, dynamic>? _selectedCustomer;
  DateTime? _requestDate;
  DateTime? _dispatchDate;
  DateTime? _invoiceDate;

  List<Item> _allItems = [];
  List<Map<String, dynamic>> _selectedItems = [];
  final _quantityController = TextEditingController();

  // ignore: unused_field
  Item? _selectedItem;

  Map<String, String> _customerIdMap = {};
  List<Map<String, dynamic>> _customers = [];
  final List<bool> _stepValid = [false, false, false]; // track validation

  void _loadCustomers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('customers')
        .get();

    if (mounted) {
      setState(() {
        _customers = [];
        _customerIdMap = {};
        for (var doc in snapshot.docs) {
          final data = doc.data(); // full customer map
          final name = data['name'];

          _customers.add(data); // store full map
          _customerIdMap[name] = doc.id; // optional: for ID use
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _itemDescriptionController.dispose();
    _itemQuantityController.dispose();
    _deliveryInstructionController.dispose();
    _invoiceNumberController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _checkRemarks(double totalAmount) async {
    final creditLimit = _creditLimit;
    final accountNumber = _accountNumber;
    await fetchAccountReceivable(accountNumber!);
    final amountDue = _amountDue! + totalAmount;
    final over30Days = _over30Days;
    final unsecuredFunds = _unsecuredFunds;

    if (creditLimit != null && amountDue > creditLimit) {
      _remark1 = 'OCL';
    } else {
      _remark1 = null;
    }
    if (over30Days! > 0 || unsecuredFunds! > 0) {
      _remark2 = 'Past Due / Unsecured';
    } else {
      _remark2 = null;
    }

    if (mounted) {
      setState(() {
        _currentStep += 1;
      });
    }
  }

  double _calculateTotal() {
    double total = 0;
    for (var item in _selectedItems) {
      final subtotal = item['subtotal'] ?? 0;
      total += (subtotal is num) ? subtotal.toDouble() : 0;
    }
    return total;
  }

  Future<String> generateSORNumber(String accountNumber) async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyMMdd').format(now); // '250620'

    // Build prefix: PAC001-250620-
    // final prefix = '$accountNumber-$dateStr';
    final prefix = 'HDI1-$dateStr';

    // Query Firestore for count of existing SORs with that prefix
    final snapshot = await FirebaseFirestore.instance
        .collection('salesRequisitions')
        .where('sorNumber', isGreaterThanOrEqualTo: '$prefix-000')
        .where('sorNumber', isLessThanOrEqualTo: '$prefix-999')
        .get();

    final count = snapshot.docs.length + 1;
    final paddedCount = count.toString().padLeft(3, '0');

    return '$prefix-$paddedCount';
  }

  Future<void> fetchAccountReceivable(String accountNumber) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('accountReceivable')
        .where('accountNumber', isEqualTo: accountNumber)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty && mounted) {
      final data = snapshot.docs.first.data();
      setState(() {
        _amountDue = (data['amountDue'] ?? 0).toDouble();
        _over30Days = (data['overThirtyDays'] ?? 0).toDouble();
        _unsecuredFunds = (data['unsecured'] ?? 0).toDouble();
      });
    } else {
      setState(() {
        _amountDue = 0;
        _over30Days = 0;
        _unsecuredFunds = 0;
      });
    }
  }

  void _confirmAndSubmit() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Submission'),
        content: const Text('Are you sure you want to submit this form?'),
        actions: [
          TextButton(
            onPressed: () {
              if (!mounted) return;
              Navigator.of(context).pop(); // Close dialog
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!mounted) return;
              Navigator.of(context).pop(); // Close dialog
              _submitForm(); // Proceed with actual submission
            },
            child: const Text('Yes, Submit'),
          ),
        ],
      ),
    );
  }

  void _showQuantityInput(Item item) async {
    if (_selectedCustomer == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer first')),
      );
      return;
    }

    final priceLevelMap = {
      'specialODPrice': 'specialOD',
      'rmlInclusivePrice': 'rmlInclusivePrice',
      'regularPrice': 'regularPrice',
    };

    final rawPriceLevel = _selectedCustomer?['priceLevel'] ?? 'regularPrice';
    final firestorePriceKey = priceLevelMap[rawPriceLevel] ?? 'regularPrice';

    final itemData = await FirestoreService().fetchItemPrice(item.code);

    if (!mounted) return;
    if (itemData == null || !itemData.containsKey(firestorePriceKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No pricing info available for item ${item.name}'),
        ),
      );
      return;
    }

    final autoPrice = (itemData[firestorePriceKey] ?? 0).toDouble();

    final qtyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final qty = int.tryParse(qtyController.text) ?? 0;

              if (qty <= 0) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Quantity must be greater than 0'),
                  ),
                );
                return;
              } else if (qty > item.stock) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Quantity cannot exceed available stock (Stock: ${item.stock}).',
                    ),
                  ),
                );
                return;
              }
              setState(() {
                _selectedItems.removeWhere((e) => e['id'] == item.id);
                final existingIndex = _selectedItems.indexWhere(
                  (e) => e['id'] == item.id,
                );
                final data = {
                  'id': item.id,
                  'name': item.name,
                  'code': item.code,
                  'quantity': qty,
                  'unitPrice': autoPrice,
                  'subtotal': qty * autoPrice,
                };
                if (existingIndex != -1) {
                  _selectedItems[existingIndex] = data;
                } else {
                  _selectedItems.add(data);
                }
              });
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showCustomerSearchDialog() {
    String query = '';
    List<Map<String, dynamic>> filteredCustomers = [..._customers];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Select Customer'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search customer',
                      ),
                      onChanged: (value) {
                        query = value.toLowerCase();
                        setStateDialog(() {
                          filteredCustomers = _customers
                              .where(
                                (customer) => customer['name']
                                    .toLowerCase()
                                    .contains(query),
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
                            subtitle: Text(
                              'Acct #: ${customer['accountNumber']}',
                            ),
                            onTap: () async {
                              setState(() {
                                _selectedCustomer = customer;
                                _accountNumber = customer['accountNumber'];
                                _creditLimit =
                                    customer['creditLimit']?.toDouble() ?? 0;
                              });

                              final customerName = customer['name'];
                              final docId = _customerIdMap[customerName];
                              if (docId != null) {
                                final doc = await FirebaseFirestore.instance
                                    .collection('customers')
                                    .doc(docId)
                                    .get();
                                final account = doc['accountNumber'];
                                final generatedSOR = await generateSORNumber(
                                  account,
                                );

                                if (!mounted) return;
                                setState(() {
                                  _accountNumber = account;
                                  _sorNumber = generatedSOR;
                                });
                              }
                              if (!mounted) return;
                              // ignore: use_build_context_synchronously
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
                  onPressed: () {
                    if (!mounted) return;
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _editSelectedItemQuantity(int index) {
    final currentItem = _selectedItems[index];
    final TextEditingController editController = TextEditingController(
      text: currentItem['quantity'].toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Quantity: ${currentItem['name']}'),
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

              setState(() {
                _selectedItems[index]['quantity'] = newQty;
                _selectedItems[index]['subtotal'] =
                    newQty * currentItem['unitPrice'];
              });

              Navigator.pop(context);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitForm() async {
    if (_selectedCustomer == null || _selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields.')),
      );
      return;
    }

    try {
      final now = Timestamp.now();
      final formData = {
        'customerName': _selectedCustomer!['name'],
        'accountNumber': _selectedCustomer!['accountNumber'],
        'area': _selectedCustomer!['area'],
        'creditLimit': _creditLimit,
        'paymentTerms': _selectedCustomer!['paymentTerms'],
        'postalAddress': _selectedCustomer!['postalAddress'],
        'sorNumber': _sorNumber,
        'requestDate': _requestDate,
        'dispatchDate': _dispatchDate,
        'invoiceDate': _invoiceDate,
        'remark1': _remark1,
        'remark2': _remark2,
        'items': _selectedItems
            .map(
              (item) => {
                'id': item['id'],
                'code': item['code'],
                'name': item['name'],
                'unitPrice': item['unitPrice'],
                'quantity': item['quantity'],
                'subtotal': item['subtotal'],
              },
            )
            .toList(),
        'totalAmount': _calculateTotal(),
        'userID': FirebaseAuth.instance.currentUser?.uid,
        'timeStamp': now,
      };

      await FirebaseFirestore.instance
          .collection('salesRequisitions')
          .add(formData);
      // ✅
      // Update inventory for each item
      for (final item in _selectedItems) {
        final itemId = item['id'];
        final purchasedQty = item['quantity'] ?? 0;

        final itemRef = FirebaseFirestore.instance
            .collection('itemsAvailable')
            .doc(itemId);
        final itemSnapshot = await itemRef.get();

        if (itemSnapshot.exists) {
          final currentStock = itemSnapshot.data()?['quantity'] ?? 0;
          final updatedStock = (currentStock - purchasedQty).clamp(
            0,
            double.infinity,
          );

          await itemRef.update({'quantity': updatedStock});
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Form submitted successfully!')),
      );

      // Optional: reset form
      setState(() {
        _selectedCustomer = null;
        _selectedItems = [];
        _remark1 = '';
        _remark2 = '';
        _sorNumber = '';
        _invoiceDate = null;
        _requestDate = null;
        _dispatchDate = null;
      });

      if (!mounted) return;
      Navigator.pop(context); // Go back to dashboard or previous page
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submission failed: $e')));
    }
  }

  Widget _buildCustomerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer Info',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _showCustomerSearchDialog,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Customer',
              border: OutlineInputBorder(),
            ),
            child: Text(
              _selectedCustomer?['name'] ?? 'Select a customer',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // if (_accountNumber != null) Text('Account #: $_accountNumber'),
        if (_area != null) Text('Area: $_area'),
        if (_paymentTerms != null) Text('Terms: $_paymentTerms'),
        // if (_creditLimit != null) Text('Credit Limit: ₱$_creditLimit'),
      ],
    );
  }

  Widget _buildItemsSection() {
    double total = _selectedItems.fold(
      0.0,
      (currentTotal, item) => currentTotal + (item['subtotal'] ?? 0.0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 500,
          child: FutureBuilder<List<Item>>(
            future: FirestoreService().fetchItems(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return const Text('Error loading items');
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Text(
                  'No items found.',
                ); // Or some other placeholder
              }

              _allItems = snapshot.data!;
              // print('Items passed to ItemSelector: $_allItems'); // Verify for debugging
              return ItemSelector(
                items: _allItems, // <--- Crucial part
                onItemSelected: (item) {
                  if (item.stock > 0) {
                    setState(() {
                      _selectedItem = item;
                    });
                    _showQuantityInput(item);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'This item is out of stock and cannot be selected.',
                        ),
                      ),
                    );
                  }
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Selected Items:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),

        ..._selectedItems.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;

          return Card(
            child: ListTile(
              title: Text(item['name']),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Qty: ${item['quantity']}'),
                  Text('Unit Price: ₱${item['unitPrice'].toStringAsFixed(2)}'),
                  Text('Subtotal: ₱${item['subtotal'].toStringAsFixed(2)}'),
                ],
              ),
              trailing: Wrap(
                spacing: 12,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _editSelectedItemQuantity(index),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _selectedItems.removeAt(index);
                      });
                    },
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
        Text(
          'Total: ₱${total.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }

  bool _isCurrentStepValid(int step) {
    if (step == 0 && _selectedCustomer != null) {
      return true;
    } else if (step == 0 && _selectedCustomer == null) {
      return false;
    }
    return true;
  }

  void _handleStepContinue() async {
    final isGoingToFinalStep = _currentStep + 1 == _buildSteps().length - 1;
    if (isGoingToFinalStep) {
      final total = _calculateTotal();
      await _checkRemarks(total);
    } else if (_currentStep < _buildSteps().length - 1) {
      setState(() {
        _currentStep += 1;
      });
    }
  }

  List<Step> _buildSteps() {
    return [
      Step(
        title: const Text('Customer'),
        content: _buildCustomerSection(),
        state: _stepValid[0]
            ? StepState.complete
            : (_currentStep == 0 ? StepState.editing : StepState.indexed),
        isActive: _currentStep >= 0,
      ),
      Step(
        title: const Text('Items'),
        content: _buildItemsSection(),
        state: _allItems.isNotEmpty
            ? StepState.complete
            : (_currentStep == 1 ? StepState.editing : StepState.indexed),
        isActive: _currentStep >= 1,
      ),
      Step(
        title: const Text('Review & Submit'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SOR Number: ${_sorNoController.text}'),
            Text('Total: ₱${_calculateTotal().toStringAsFixed(2)}'),
            const SizedBox(height: 10),
            if (_sorNumber != null) Text('SOR #: $_sorNumber'),
            if (_accountNumber != null) Text('Account #: $_accountNumber'),
            if (_remark1 != null)
              Text('Remark 1: $_remark1', style: TextStyle(color: Colors.red)),
            if (_remark2 != null)
              Text('Remark 2: $_remark2', style: TextStyle(color: Colors.red)),
            const SizedBox(height: 20),
          ],
        ),
        state: _allItems.isNotEmpty
            ? StepState.complete
            : (_currentStep == 2 ? StepState.editing : StepState.indexed),
        isActive: _currentStep >= 2,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sales Requisition Form')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: _formKey,
                child: Stepper(
                  type: StepperType.horizontal,
                  steps: _buildSteps(),
                  currentStep: _currentStep,
                  onStepContinue: _handleStepContinue,
                  onStepCancel: () {
                    if (_currentStep > 0) {
                      setState(() => _currentStep -= 1);
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  controlsBuilder: (context, details) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (_currentStep > 0)
                            OutlinedButton(
                              onPressed: details.onStepCancel,
                              child: const Text('Back'),
                            ),
                          const SizedBox(width: 10),
                          if (_currentStep < _buildSteps().length - 1)
                            OutlinedButton(
                              onPressed: () {
                                if (_isCurrentStepValid(_currentStep)) {
                                  details.onStepContinue?.call();
                                } else {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Please complete this step before continuing.',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: const Text('Next'),
                            )
                          else if (_currentStep == _buildSteps().length - 1)
                            OutlinedButton(
                              onPressed: () {
                                if (!mounted) return;
                                _confirmAndSubmit();
                              },
                              child: const Text('Submit'),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
