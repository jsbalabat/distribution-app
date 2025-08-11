import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../models/item_model.dart';
import '../widgets/customer_section.dart';
import '../widgets/items_section.dart';
import '../widgets/review_section.dart';
import '../widgets/quantity_input_dialog.dart';
import '../widgets/customer_search_dialog.dart';
import '../widgets/edit_quantity_dialog.dart';
import '../widgets/confirmation_dialog.dart';

class FormStepData {
  final String title;
  final Widget content;

  FormStepData({required this.title, required this.content});
}

class FormScreen extends StatefulWidget {
  const FormScreen({super.key});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

enum ErrorType { validation, network, permission, storage, unknown }

class _FormScreenState extends State<FormScreen> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;

  final _deliveryInstructionController = TextEditingController();
  final _invoiceNumberController = TextEditingController();
  final _itemDescriptionController = TextEditingController();
  final _itemQuantityController = TextEditingController();

  String? _remark1;
  String? _remark2;
  String? _accountNumber;
  String? _sorNumber;
  double? _creditLimit;
  double? _amountDue;
  double? _over30Days;
  double? _unsecuredFunds;

  Map<String, dynamic>? _selectedCustomer;
  DateTime? _requestDate;
  DateTime? _dispatchDate;
  DateTime? _invoiceDate;

  List<Item> _allItems = [];
  bool _isLoadingItems = false;
  String? _itemLoadError;

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

  // Centralized error handling
  void handleError(
    BuildContext context,
    String message, {
    ErrorType type = ErrorType.unknown,
  }) {
    // Customize message based on error type
    String displayMessage;

    switch (type) {
      case ErrorType.validation:
        displayMessage = 'Validation error: $message';
        break;
      case ErrorType.network:
        displayMessage =
            'Network error: $message. Please check your connection.';
        break;
      case ErrorType.permission:
        displayMessage = 'Permission denied: $message';
        break;
      case ErrorType.storage:
        displayMessage = 'Storage error: $message';
        break;
      case ErrorType.unknown:
        displayMessage = 'Error: $message';
        break;
    }

    // Log error (in a real app, you might want to use a logging service)
    debugPrint('Error: $displayMessage');

    // Show snackbar to user
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(displayMessage),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Added method to fetch items in parent
  Future<void> _loadItems() async {
    if (_isLoadingItems) return;

    setState(() {
      _isLoadingItems = true;
      _itemLoadError = null;
    });

    try {
      final items = await FirestoreService().fetchItems();
      if (mounted) {
        setState(() {
          _allItems = items;
          _isLoadingItems = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _itemLoadError = e.toString();
          _isLoadingItems = false;
        });
        handleError(context, e.toString(), type: ErrorType.network);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _loadItems(); // Add item loading in initState
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
    try {
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
    } catch (e) {
      if (!mounted) return;
      handleError(
        context,
        'Failed to fetch account receivable data: $e',
        type: ErrorType.network,
      );
      // Set default values on error
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
      builder: (context) => ConfirmationDialog(
        title: 'Confirm Submission',
        message: 'Are you sure you want to submit this form?',
        onConfirm: _submitForm,
      ),
    );
  }

  void _showQuantityInput(Item item) async {
    if (_selectedCustomer == null) {
      if (!mounted) return;
      handleError(
        context,
        'Please select a customer first',
        type: ErrorType.validation,
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

    try {
      final itemData = await FirestoreService().fetchItemPrice(item.code);

      if (!mounted) return;
      if (itemData == null || !itemData.containsKey(firestorePriceKey)) {
        handleError(
          context,
          'No pricing info available for item ${item.name}',
          type: ErrorType.validation,
        );
        return;
      }

      final autoPrice = (itemData[firestorePriceKey] ?? 0).toDouble();

      showDialog(
        context: context,
        builder: (context) => QuantityInputDialog(
          item: item,
          autoPrice: autoPrice,
          onAdd: (qty) {
            setState(() {
              _selectedItems.removeWhere((e) => e['id'] == item.id);
              final data = {
                'id': item.id,
                'name': item.name,
                'code': item.code,
                'quantity': qty,
                'unitPrice': autoPrice,
                'subtotal': qty * autoPrice,
              };
              _selectedItems.add(data);
            });
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      handleError(
        context,
        'Failed to fetch item price: $e',
        type: ErrorType.network,
      );
    }
  }

  void _showCustomerSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => CustomerSearchDialog(
        customers: _customers,
        onCustomerSelected: (customer) async {
          setState(() {
            _selectedCustomer = customer;
            _accountNumber = customer['accountNumber'];
            _creditLimit = customer['creditLimit']?.toDouble() ?? 0;
          });

          final customerName = customer['name'];
          final docId = _customerIdMap[customerName];
          if (docId != null) {
            final doc = await FirebaseFirestore.instance
                .collection('customers')
                .doc(docId)
                .get();
            final account = doc['accountNumber'];
            final generatedSOR = await generateSORNumber(account);

            if (!mounted) return;
            setState(() {
              _accountNumber = account;
              _sorNumber = generatedSOR;
            });
          }
        },
      ),
    );
  }

  void _editSelectedItemQuantity(int index) {
    final currentItem = _selectedItems[index];

    showDialog(
      context: context,
      builder: (context) => EditQuantityDialog(
        itemName: currentItem['name'],
        currentQuantity: (currentItem['quantity'] as num).toInt(),
        onUpdate: (newQty) {
          setState(() {
            _selectedItems[index]['quantity'] = newQty;
            _selectedItems[index]['subtotal'] =
                newQty * currentItem['unitPrice'];
          });
        },
      ),
    );
  }

  // Safe state updates
  void safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  // Form validation
  Future<void> _validateForm() async {
    if (_selectedCustomer == null) {
      throw Exception('Please select a customer.');
    }

    if (_selectedItems.isEmpty) {
      throw Exception('Please select at least one item.');
    }
  }

  // Update inventory after form submission
  Future<void> _updateInventory() async {
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
  }

  Future<void> _submitForm() async {
    try {
      await _validateForm();

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

      try {
        await FirebaseFirestore.instance
            .collection('salesRequisitions')
            .add(formData);
      } catch (e) {
        if (!mounted) return;
        handleError(
          context,
          'Failed to submit form: $e',
          type: ErrorType.network,
        );
        return;
      }

      try {
        await _updateInventory();
      } catch (e) {
        if (!mounted) return;
        handleError(
          context,
          'Form was submitted but inventory update failed: $e',
          type: ErrorType.storage,
        );
        // We don't return here because the form was submitted successfully
      }

      safeSetState(() {
        // Reset form
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Form submitted successfully!')),
      );

      if (!mounted) return;
      Navigator.pop(context); // Go back to dashboard or previous page
    } catch (e) {
      if (!mounted) return;
      handleError(context, e.toString(), type: ErrorType.validation);
    }
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
    final List<FormStepData> steps = [
      FormStepData(
        title: 'Customer',
        content: CustomerSection(
          selectedCustomer: _selectedCustomer,
          onTap: _showCustomerSearchDialog,
        ),
      ),
      FormStepData(
        title: 'Items',
        content: ItemsSection(
          isLoading: _isLoadingItems,
          loadError: _itemLoadError,
          allItems: _allItems,
          selectedItems: _selectedItems,
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
          onEditQuantity: _editSelectedItemQuantity,
          onDeleteItem: (index) {
            setState(() {
              _selectedItems.removeAt(index);
            });
          },
          onRefresh: () {
            _loadItems();
            return Future.value();
          },
        ),
      ),
      FormStepData(
        title: 'Review & Submit',
        content: ReviewSection(
          totalAmount: _calculateTotal(),
          sorNumber: _sorNumber,
          accountNumber: _accountNumber,
          remark1: _remark1,
          remark2: _remark2,
        ),
      ),
    ];

    return steps.asMap().entries.map((entry) {
      final index = entry.key;
      final step = entry.value;

      return Step(
        title: Text(step.title), // No type casting needed
        content: step.content, // No type casting needed
        state: _stepValid[index]
            ? StepState.complete
            : (_currentStep == index ? StepState.editing : StepState.indexed),
        isActive: _currentStep >= index,
      );
    }).toList();
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
                                  handleError(
                                    context,
                                    'Please complete this step before continuing.',
                                    type: ErrorType.validation,
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
