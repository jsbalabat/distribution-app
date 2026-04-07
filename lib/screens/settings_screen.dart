import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../styles/app_styles.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;

  // Settings values
  bool _autoApproveOrders = false;
  bool _lowStockAlerts = true;
  bool _emailNotifications = true;
  int _lowStockThreshold = 10;
  String _companyName = '';
  String _companyEmail = '';
  String _companyPhone = '';

  final _companyNameController = TextEditingController();
  final _companyEmailController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _lowStockController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyEmailController.dispose();
    _companyPhoneController.dispose();
    _lowStockController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await _firestore
          .collection('settings')
          .doc('appSettings')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _autoApproveOrders = data['autoApproveOrders'] ?? false;
          _lowStockAlerts = data['lowStockAlerts'] ?? true;
          _emailNotifications = data['emailNotifications'] ?? true;
          _lowStockThreshold = data['lowStockThreshold'] ?? 10;
          _companyName = data['companyName'] ?? '';
          _companyEmail = data['companyEmail'] ?? '';
          _companyPhone = data['companyPhone'] ?? '';

          _companyNameController.text = _companyName;
          _companyEmailController.text = _companyEmail;
          _companyPhoneController.text = _companyPhone;
          _lowStockController.text = _lowStockThreshold.toString();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading settings: $e'),
            backgroundColor: AppStyles.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _firestore.collection('settings').doc('appSettings').set({
        'autoApproveOrders': _autoApproveOrders,
        'lowStockAlerts': _lowStockAlerts,
        'emailNotifications': _emailNotifications,
        'lowStockThreshold': int.tryParse(_lowStockController.text) ?? 10,
        'companyName': _companyNameController.text,
        'companyEmail': _companyEmailController.text,
        'companyPhone': _companyPhoneController.text,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully'),
            backgroundColor: AppStyles.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: AppStyles.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyles.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('System Settings', style: AppStyles.appBarTitleStyle),
        backgroundColor: AppStyles.adminPrimaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            onPressed: _saveSettings,
            tooltip: 'Save Settings',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppStyles.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Company Information Section
                  Text('Company Information', style: AppStyles.headingStyle),
                  const SizedBox(height: AppStyles.spacingM),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppStyles.borderRadiusMedium,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppStyles.spacingM),
                      child: Column(
                        children: [
                          TextField(
                            controller: _companyNameController,
                            decoration: const InputDecoration(
                              labelText: 'Company Name',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.business),
                            ),
                          ),
                          const SizedBox(height: AppStyles.spacingM),
                          TextField(
                            controller: _companyEmailController,
                            decoration: const InputDecoration(
                              labelText: 'Company Email',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: AppStyles.spacingM),
                          TextField(
                            controller: _companyPhoneController,
                            decoration: const InputDecoration(
                              labelText: 'Company Phone',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: AppStyles.spacingXL),

                  // Order Management Section
                  Text('Order Management', style: AppStyles.headingStyle),
                  const SizedBox(height: AppStyles.spacingM),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppStyles.borderRadiusMedium,
                      ),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Auto-Approve Orders'),
                          subtitle: const Text(
                            'Automatically approve new orders',
                          ),
                          value: _autoApproveOrders,
                          onChanged: (value) {
                            setState(() {
                              _autoApproveOrders = value;
                            });
                          },
                          secondary: const Icon(Icons.check_circle_outline),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: const Text('Email Notifications'),
                          subtitle: const Text(
                            'Send email alerts for new orders',
                          ),
                          value: _emailNotifications,
                          onChanged: (value) {
                            setState(() {
                              _emailNotifications = value;
                            });
                          },
                          secondary: const Icon(Icons.mail_outline),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppStyles.spacingXL),

                  // Inventory Management Section
                  Text('Inventory Management', style: AppStyles.headingStyle),
                  const SizedBox(height: AppStyles.spacingM),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppStyles.borderRadiusMedium,
                      ),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Low Stock Alerts'),
                          subtitle: const Text(
                            'Get notified when items run low',
                          ),
                          value: _lowStockAlerts,
                          onChanged: (value) {
                            setState(() {
                              _lowStockAlerts = value;
                            });
                          },
                          secondary: const Icon(Icons.inventory_2_outlined),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(AppStyles.spacingM),
                          child: TextField(
                            controller: _lowStockController,
                            decoration: const InputDecoration(
                              labelText: 'Low Stock Threshold',
                              helperText:
                                  'Alert when quantity falls below this number',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.warning_amber_outlined),
                              suffixText: 'units',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppStyles.spacingXL),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save),
                      label: const Text('Save All Settings'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppStyles.adminPrimaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppStyles.borderRadiusMedium,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: AppStyles.spacingXL),
                ],
              ),
            ),
    );
  }
}
