import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'dart:math';
import '../services/firestore_service.dart';
import '../models/item_model.dart';
import '../widgets/customer_section.dart';
import '../widgets/items_section.dart';
import '../widgets/review_section.dart';
import '../widgets/quantity_input_dialog.dart';
import '../widgets/customer_search_dialog.dart';
import '../widgets/edit_quantity_dialog.dart';
import '../widgets/confirmation_dialog.dart';
import '../utils/error_types.dart';
import '../styles/app_styles.dart';

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

  bool _isSubmitting = false; // Track form submission state

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
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(10),
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

    // Set default dates
    _requestDate = DateTime.now();
    _dispatchDate = DateTime.now().add(const Duration(days: 3));
    _invoiceDate = DateTime.now();
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
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyMMdd').format(now); // '250819'
      final prefix = 'HDI1-$dateStr';

      // Try a different approach to avoid permission issues
      try {
        // Instead of querying with filters, get today's submissions and filter client-side
        final snapshot = await FirebaseFirestore.instance
            .collection('salesRequisitions')
            .where('userID', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
            .get();

        // Filter matching SORs client-side
        final todayDocs = snapshot.docs.where((doc) {
          final sorNumber = (doc.data()['sorNumber'] ?? '') as String;
          return sorNumber.startsWith(prefix);
        }).toList();

        final count = todayDocs.isEmpty ? 1 : todayDocs.length + 1;
        final paddedCount = count.toString().padLeft(3, '0');
        final sorNumber = '$prefix-$paddedCount';

        return sorNumber;
      } catch (e) {
        // Second fallback - use timestamp seconds as unique identifier
        final timestamp = DateTime.now().second;
        final paddedTimestamp = timestamp.toString().padLeft(3, '0');
        return '$prefix-$paddedTimestamp';
      }
    } catch (e) {
      // Final fallback value in case of any error
      final timestamp = DateTime.now().millisecondsSinceEpoch % 1000;
      final fallbackSOR = 'HDI1-ERR-${timestamp.toString().padLeft(3, '0')}';
      return fallbackSOR;
    }
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
      setState(() {
        _isSubmitting = true;
      });

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
        setState(() {
          _isSubmitting = false;
        });
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

      setState(() {
        _isSubmitting = false;
      });

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
        const SnackBar(
          content: Text('Form submitted successfully!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          margin: EdgeInsets.all(10),
        ),
      );

      if (!mounted) return;
      Navigator.pop(context); // Go back to dashboard or previous page
    } catch (e) {
      if (!mounted) return;
      handleError(context, e.toString(), type: ErrorType.validation);
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  bool _isCurrentStepValid(int step) {
    if (step == 0) {
      if (_selectedCustomer != null) {
        _stepValid[0] = true;
        return true;
      } else {
        _stepValid[0] = false;
        return false;
      }
    } else if (step == 1) {
      if (_selectedItems.isNotEmpty) {
        _stepValid[1] = true;
        return true;
      } else {
        _stepValid[1] = false;
        return false;
      }
    }
    return true;
  }

  void _handleStepContinue() async {
    if (!_isCurrentStepValid(_currentStep)) {
      handleError(
        context,
        'Please complete this step before continuing.',
        type: ErrorType.validation,
      );
      return;
    }

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

  Future<void> _selectDate(BuildContext context, int dateType) async {
    DateTime? initialDate;

    if (dateType == 1) {
      // Request Date
      initialDate = _requestDate ?? DateTime.now();
    } else if (dateType == 2) {
      // Dispatch Date
      initialDate =
          _dispatchDate ?? DateTime.now().add(const Duration(days: 3));
    } else {
      // Invoice Date
      initialDate = _invoiceDate ?? DateTime.now();
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2025),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppStyles.primaryColor,
              onPrimary: Colors.white,
              surface: AppStyles.cardColor,
              onSurface: AppStyles.textColor,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: AppStyles.cardColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        if (dateType == 1) {
          _requestDate = picked;
        } else if (dateType == 2) {
          _dispatchDate = picked;
        } else {
          _invoiceDate = picked;
        }
      });
    }
  }

  List<Step> _buildSteps() {
    final dateFormat = DateFormat('MMM d, yyyy');
    final List<FormStepData> steps = [
      FormStepData(
        title: 'Customer',
        content: Column(
          children: [
            CustomerSection(
              selectedCustomer: _selectedCustomer,
              onTap: _showCustomerSearchDialog,
            ),
            if (_selectedCustomer != null) ...[
              const SizedBox(height: 24),
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
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

                      // Request Date
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
                                'Request Date',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _selectDate(context, 1),
                              icon: const Icon(
                                Icons.edit_calendar,
                                size: 16,
                                color: AppStyles.primaryColor,
                              ),
                              label: Text(
                                _requestDate != null
                                    ? dateFormat.format(_requestDate!)
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
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Dispatch Date',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _selectDate(context, 2),
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

                      // Invoice Date
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
                                'Invoice Date',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _selectDate(context, 3),
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
                    ],
                  ),
                ),
              ),
            ],
          ],
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
                SnackBar(
                  content: const Text(
                    'This item is out of stock and cannot be selected.',
                  ),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  margin: const EdgeInsets.all(10),
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
        title: 'Review',
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

      // Determine icon
      // IconData stepIcon;
      // if (index == 0) {
      //   stepIcon = Icons.person;
      // } else if (index == 1) {
      //   stepIcon = Icons.shopping_cart;
      // } else {
      //   stepIcon = Icons.assignment;
      // }

      return Step(
        title: Text(
          step.title,
          style: TextStyle(
            color: _currentStep == index
                ? AppStyles.primaryColor
                : AppStyles.textColor,
            fontWeight: _currentStep == index
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
        content: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 24),
          child: step.content,
        ),
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
      backgroundColor: AppStyles.backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppStyles.primaryColor,
        title: const Row(
          children: [
            Icon(Icons.assignment, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'New Sales Requisition',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: AppStyles.primaryColor.withValues(alpha: 0.05),
                border: Border(
                  bottom: BorderSide(
                    color: AppStyles.primaryColor.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'Step ${_currentStep + 1} of 3',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppStyles.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (_currentStep + 1) / 3,
                      backgroundColor: Colors.grey[200],
                      color: AppStyles.primaryColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Form(
                key: _formKey,
                child: Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: AppStyles.primaryColor,
                    ),
                  ),
                  child: Stepper(
                    type: StepperType.horizontal,
                    steps: _buildSteps(),
                    currentStep: _currentStep,
                    onStepContinue: _handleStepContinue,
                    onStepCancel: () {
                      if (_currentStep > 0) {
                        setState(() => _currentStep -= 1);
                      } else {
                        // Show confirmation before leaving
                        if (_selectedCustomer != null ||
                            _selectedItems.isNotEmpty) {
                          showDialog(
                            context: context,
                            builder: (context) => ConfirmationDialog(
                              title: 'Discard Changes',
                              message:
                                  'Are you sure you want to discard this form?',
                              onConfirm: () {
                                Navigator.of(context).pop();
                              },
                            ),
                          );
                        } else {
                          Navigator.pop(context);
                        }
                      }
                    },
                    controlsBuilder: (context, details) {
                      return Container(
                        margin: const EdgeInsets.only(top: 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 5,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isSubmitting
                                    ? null
                                    : details.onStepCancel,
                                icon: const Icon(Icons.arrow_back),
                                label: Text(
                                  _currentStep == 0 ? 'Cancel' : 'Back',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppStyles.secondaryColor,
                                  side: const BorderSide(
                                    color: AppStyles.secondaryColor,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isSubmitting
                                    ? null
                                    : () {
                                        if (_currentStep <
                                            _buildSteps().length - 1) {
                                          details.onStepContinue?.call();
                                        } else {
                                          _confirmAndSubmit();
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppStyles.primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: _isSubmitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        _currentStep == _buildSteps().length - 1
                                            ? Icons.check
                                            : Icons.arrow_forward,
                                      ),
                                label: Text(
                                  _isSubmitting
                                      ? 'Processing...'
                                      : (_currentStep ==
                                                _buildSteps().length - 1
                                            ? 'Submit'
                                            : 'Continue'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
