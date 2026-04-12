import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../services/audit_service.dart';
import '../services/firestore_tenant.dart';
import '../styles/app_styles.dart';
import '../utils/admin_navigation.dart';
import '../widgets/admin_desktop_shell.dart';
import '../widgets/admin_screen_guard.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _firestore = FirestoreTenant.instance.firestore;
  final _auditService = AuditService();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;

  // Settings values
  bool _autoApproveOrders = false;
  bool _lowStockAlerts = true;
  bool _emailNotifications = true;
  int _lowStockThreshold = 10;
  int _auditLogRetentionDays = 180;
  bool _scheduledMaintenanceEnabled = true;
  int _scheduledCleanupHour = 0;
  int _scheduledCleanupMinute = 0;
  int _maintenanceRetentionDays = 30;
  String _companyName = '';
  String _companyEmail = '';
  String _companyPhone = '';

  final _companyNameController = TextEditingController();
  final _companyEmailController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _lowStockController = TextEditingController();
  final _auditLogRetentionController = TextEditingController();
  final _scheduledCleanupHourController = TextEditingController();
  final _scheduledCleanupMinuteController = TextEditingController();
  final _maintenanceRetentionController = TextEditingController();

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
    _auditLogRetentionController.dispose();
    _scheduledCleanupHourController.dispose();
    _scheduledCleanupMinuteController.dispose();
    _maintenanceRetentionController.dispose();
    super.dispose();
  }

  int _parseRetentionDays(String value) {
    final parsed = int.tryParse(value) ?? 180;
    if (parsed < 30) return 30;
    if (parsed > 3650) return 3650;
    return parsed;
  }

  int _parseMaintenanceRetentionDays(String value) {
    final parsed = int.tryParse(value) ?? 30;
    if (parsed < 1) return 1;
    if (parsed > 3650) return 3650;
    return parsed;
  }

  int _parseHour(String value) {
    final parsed = int.tryParse(value) ?? 0;
    if (parsed < 0) return 0;
    if (parsed > 23) return 23;
    return parsed;
  }

  int _parseMinute(String value) {
    final parsed = int.tryParse(value) ?? 0;
    if (parsed < 0) return 0;
    if (parsed > 59) return 59;
    return parsed;
  }

  String? _validateRequired(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Company email is required.';
    if (!text.contains('@') || !text.contains('.')) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Company phone is required.';
    if (!RegExp(r'^[0-9+()\-\s]{7,}$').hasMatch(text)) {
      return 'Enter a valid phone number.';
    }
    return null;
  }

  String? _validateIntRange(
    String? value, {
    required String label,
    required int min,
    required int max,
  }) {
    final text = value?.trim() ?? '';
    final parsed = int.tryParse(text);
    if (parsed == null) {
      return '$label must be a number.';
    }
    if (parsed < min || parsed > max) {
      return '$label must be between $min and $max.';
    }
    return null;
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
          _auditLogRetentionDays = data['auditLogRetentionDays'] ?? 180;
          _scheduledMaintenanceEnabled =
              data['scheduledMaintenanceEnabled'] ?? true;
          _scheduledCleanupHour = data['scheduledCleanupHour'] ?? 0;
          _scheduledCleanupMinute = data['scheduledCleanupMinute'] ?? 0;
          _maintenanceRetentionDays = data['maintenanceRetentionDays'] ?? 30;
          _companyName = data['companyName'] ?? '';
          _companyEmail = data['companyEmail'] ?? '';
          _companyPhone = data['companyPhone'] ?? '';

          _companyNameController.text = _companyName;
          _companyEmailController.text = _companyEmail;
          _companyPhoneController.text = _companyPhone;
          _lowStockController.text = _lowStockThreshold.toString();
          _auditLogRetentionController.text = _auditLogRetentionDays.toString();
          _scheduledCleanupHourController.text = _scheduledCleanupHour
              .toString();
          _scheduledCleanupMinuteController.text = _scheduledCleanupMinute
              .toString();
          _maintenanceRetentionController.text = _maintenanceRetentionDays
              .toString();
          _isLoading = false;
        });
      } else {
        setState(() {
          _auditLogRetentionController.text = _auditLogRetentionDays.toString();
          _scheduledCleanupHourController.text = _scheduledCleanupHour
              .toString();
          _scheduledCleanupMinuteController.text = _scheduledCleanupMinute
              .toString();
          _maintenanceRetentionController.text = _maintenanceRetentionDays
              .toString();
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
    final lowStockThreshold = int.tryParse(_lowStockController.text) ?? 10;
    final auditLogRetentionDays = _parseRetentionDays(
      _auditLogRetentionController.text,
    );
    final scheduledCleanupHour = _parseHour(
      _scheduledCleanupHourController.text,
    );
    final scheduledCleanupMinute = _parseMinute(
      _scheduledCleanupMinuteController.text,
    );
    final maintenanceRetentionDays = _parseMaintenanceRetentionDays(
      _maintenanceRetentionController.text,
    );

    try {
      await _firestore.collection('settings').doc('appSettings').set({
        'autoApproveOrders': _autoApproveOrders,
        'lowStockAlerts': _lowStockAlerts,
        'emailNotifications': _emailNotifications,
        'lowStockThreshold': lowStockThreshold,
        'auditLogRetentionDays': auditLogRetentionDays,
        'scheduledMaintenanceEnabled': _scheduledMaintenanceEnabled,
        'scheduledCleanupHour': scheduledCleanupHour,
        'scheduledCleanupMinute': scheduledCleanupMinute,
        'maintenanceRetentionDays': maintenanceRetentionDays,
        'companyName': _companyNameController.text,
        'companyEmail': _companyEmailController.text,
        'companyPhone': _companyPhoneController.text,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      _auditLogRetentionController.text = auditLogRetentionDays.toString();
      _scheduledCleanupHourController.text = scheduledCleanupHour.toString();
      _scheduledCleanupMinuteController.text = scheduledCleanupMinute
          .toString();
      _maintenanceRetentionController.text = maintenanceRetentionDays
          .toString();

      await _auditService.logAction(
        action: 'update',
        entityType: 'settings',
        entityId: 'appSettings',
        details: {
          'autoApproveOrders': _autoApproveOrders,
          'lowStockAlerts': _lowStockAlerts,
          'emailNotifications': _emailNotifications,
          'lowStockThreshold': lowStockThreshold,
          'auditLogRetentionDays': auditLogRetentionDays,
          'scheduledMaintenanceEnabled': _scheduledMaintenanceEnabled,
          'scheduledCleanupHour': scheduledCleanupHour,
          'scheduledCleanupMinute': scheduledCleanupMinute,
          'maintenanceRetentionDays': maintenanceRetentionDays,
        },
      );

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

  Future<void> _handleSaveSettings() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    await _saveSettings();
  }

  void _navigateDesktop(AdminShellSection section) {
    navigateToAdminSection(
      context,
      section,
      currentSection: AdminShellSection.settings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >=
      AdminDesktopShell.desktopBreakpoint;
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: SingleChildScrollView(
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
                          TextFormField(
                            controller: _companyNameController,
                            decoration: const InputDecoration(
                              labelText: 'Company Name',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.business),
                            ),
                            validator: (value) =>
                                _validateRequired(value, 'Company name'),
                          ),
                          const SizedBox(height: AppStyles.spacingM),
                          TextFormField(
                            controller: _companyEmailController,
                            decoration: const InputDecoration(
                              labelText: 'Company Email',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: AppStyles.spacingM),
                          TextFormField(
                            controller: _companyPhoneController,
                            decoration: const InputDecoration(
                              labelText: 'Company Phone',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            keyboardType: TextInputType.phone,
                            validator: _validatePhone,
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
                          child: TextFormField(
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
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (value) => _validateIntRange(
                              value,
                              label: 'Low stock threshold',
                              min: 1,
                              max: 100000,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppStyles.spacingXL),

                  // System Maintenance Section
                  Text('System Maintenance', style: AppStyles.headingStyle),
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
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Enable Scheduled Maintenance Cleanup',
                            ),
                            subtitle: const Text(
                              'Automatically prune old maintenance/import records every day',
                            ),
                            value: _scheduledMaintenanceEnabled,
                            onChanged: (value) {
                              setState(() {
                                _scheduledMaintenanceEnabled = value;
                              });
                            },
                            secondary: const Icon(Icons.schedule_outlined),
                          ),
                          const SizedBox(height: AppStyles.spacingM),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _scheduledCleanupHourController,
                                  decoration: const InputDecoration(
                                    labelText: 'Cleanup Hour',
                                    helperText: '0 to 23',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(
                                      Icons.access_time_outlined,
                                    ),
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(2),
                                  ],
                                  validator: (value) => _validateIntRange(
                                    value,
                                    label: 'Cleanup hour',
                                    min: 0,
                                    max: 23,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppStyles.spacingM),
                              Expanded(
                                child: TextFormField(
                                  controller: _scheduledCleanupMinuteController,
                                  decoration: const InputDecoration(
                                    labelText: 'Cleanup Minute',
                                    helperText: '0 to 59',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.timelapse_outlined),
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(2),
                                  ],
                                  validator: (value) => _validateIntRange(
                                    value,
                                    label: 'Cleanup minute',
                                    min: 0,
                                    max: 59,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppStyles.spacingM),
                          TextFormField(
                            controller: _maintenanceRetentionController,
                            decoration: const InputDecoration(
                              labelText: 'Maintenance Retention',
                              helperText:
                                  'Days to keep cleanup/import logs (minimum 1, maximum 3650)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.auto_delete_outlined),
                              suffixText: 'days',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (value) => _validateIntRange(
                              value,
                              label: 'Maintenance retention',
                              min: 1,
                              max: 3650,
                            ),
                          ),
                          const SizedBox(height: AppStyles.spacingM),
                          TextFormField(
                            controller: _auditLogRetentionController,
                            decoration: const InputDecoration(
                              labelText: 'Audit Log Retention',
                              helperText:
                                  'Days to keep audit logs (minimum 30, maximum 3650)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(
                                Icons.history_toggle_off_outlined,
                              ),
                              suffixText: 'days',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (value) => _validateIntRange(
                              value,
                              label: 'Audit log retention',
                              min: 30,
                              max: 3650,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: AppStyles.spacingXL),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _handleSaveSettings,
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

    final screen = isDesktop
        ? AdminDesktopShell(
            title: 'System Settings',
            selectedSection: AdminShellSection.settings,
            onNavigate: _navigateDesktop,
            actions: [
              IconButton(
                icon: const Icon(Icons.save_outlined, color: Colors.white),
                onPressed: _handleSaveSettings,
                tooltip: 'Save Settings',
              ),
            ],
            content: body,
          )
        : Scaffold(
            backgroundColor: AppStyles.scaffoldBackgroundColor,
            appBar: AppBar(
              title: const Text(
                'System Settings',
                style: AppStyles.appBarTitleStyle,
              ),
              backgroundColor: AppStyles.adminPrimaryColor,
              iconTheme: const IconThemeData(color: Colors.white),
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.save_outlined),
                  onPressed: _handleSaveSettings,
                  tooltip: 'Save Settings',
                ),
              ],
            ),
            body: body,
          );

    return AdminScreenGuard(title: 'System Settings', child: screen);
  }
}
