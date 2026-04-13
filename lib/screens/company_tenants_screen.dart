import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../services/firestore_tenant.dart';
import '../styles/app_styles.dart';
import '../utils/app_logger.dart';

class CompanyTenantsScreen extends StatefulWidget {
  const CompanyTenantsScreen({super.key});

  @override
  State<CompanyTenantsScreen> createState() => _CompanyTenantsScreenState();
}

class _CompanyTenantsScreenState extends State<CompanyTenantsScreen> {
  final _directoryDb = FirebaseFirestore.instance;

  String _normalizeIdentifier(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      '-',
    );
    return normalized.replaceAll(RegExp(r'[^a-z0-9-]'), '');
  }

  Future<void> _openTenantEditor({
    QueryDocumentSnapshot<Map<String, dynamic>>? existing,
  }) async {
    final currentUser = context.read<UserProvider>().currentUser;
    final existingData = existing?.data() ?? <String, dynamic>{};
    final identifierController = TextEditingController(
      text: existing?.id ?? '',
    );
    final companyNameController = TextEditingController(
      text: (existingData['companyName'] ?? '').toString(),
    );
    final databaseIdController = TextEditingController(
      text:
          (existingData['firestoreDatabaseId'] ??
                  existingData['databaseId'] ??
                  '')
              .toString(),
    );

    bool isActive = existingData['isActive'] != false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppStyles.borderRadiusMedium,
                ),
              ),
              title: Text(
                existing == null
                    ? 'Create Company Tenant'
                    : 'Edit Company Tenant',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: identifierController,
                      enabled: existing == null,
                      decoration: const InputDecoration(
                        labelText: 'Company Identifier',
                        helperText: 'lowercase letters, numbers, hyphen',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppStyles.spacingM),
                    TextField(
                      controller: companyNameController,
                      decoration: const InputDecoration(
                        labelText: 'Company Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppStyles.spacingM),
                    TextField(
                      controller: databaseIdController,
                      decoration: const InputDecoration(
                        labelText: 'Firestore Database ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppStyles.spacingS),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Identifier Active'),
                      subtitle: const Text(
                        'Disable to block new sign-ins for this company',
                      ),
                      value: isActive,
                      onChanged: (value) {
                        setDialogState(() {
                          isActive = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      identifierController.dispose();
      companyNameController.dispose();
      databaseIdController.dispose();
      return;
    }

    final identifier = _normalizeIdentifier(identifierController.text);
    final companyName = companyNameController.text.trim();
    final databaseId = databaseIdController.text.trim();

    identifierController.dispose();
    companyNameController.dispose();
    databaseIdController.dispose();

    if (identifier.isEmpty || companyName.isEmpty || databaseId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Identifier, company name, and database ID are required.',
          ),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('upsertCompanyTenant');
      await callable.call(<String, dynamic>{
        'companyIdentifier': identifier,
        'companyName': companyName,
        'firestoreDatabaseId': databaseId,
        'isActive': isActive,
        'actorCompanyIdentifier': currentUser?.companyId,
        'actorDatabaseId': FirestoreTenant.instance.databaseId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Company tenant created.'
                : 'Company tenant updated.',
          ),
          backgroundColor: AppStyles.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to save company tenant',
        error: error,
        stackTrace: stackTrace,
        tag: 'TENANT',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save company tenant: $error'),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleTenantActive(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    bool nextValue,
  ) async {
    final data = doc.data();
    final user = context.read<UserProvider>().currentUser;

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('upsertCompanyTenant');
      await callable.call(<String, dynamic>{
        'companyIdentifier': doc.id,
        'companyName': (data['companyName'] ?? '').toString(),
        'firestoreDatabaseId':
            (data['firestoreDatabaseId'] ?? data['databaseId'] ?? '')
                .toString(),
        'isActive': nextValue,
        'actorCompanyIdentifier': user?.companyId,
        'actorDatabaseId': FirestoreTenant.instance.databaseId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nextValue ? 'Tenant enabled.' : 'Tenant disabled.'),
          backgroundColor: AppStyles.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to toggle tenant status',
        error: error,
        stackTrace: stackTrace,
        tag: 'TENANT',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update tenant status: $error'),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyles.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Company Tenants', style: AppStyles.appBarTitleStyle),
        backgroundColor: AppStyles.adminPrimaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Create Tenant',
            onPressed: () => _openTenantEditor(),
            icon: const Icon(Icons.add_business_outlined),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _directoryDb
            .collection('companyTenants')
            .orderBy('companyName')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error loading tenants: ${snapshot.error}'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs =
              snapshot.data?.docs ??
              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppStyles.spacingL),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.apartment_outlined,
                      size: 52,
                      color: AppStyles.textLightColor,
                    ),
                    const SizedBox(height: AppStyles.spacingM),
                    const Text('No company tenants found.'),
                    const SizedBox(height: AppStyles.spacingS),
                    ElevatedButton.icon(
                      onPressed: () => _openTenantEditor(),
                      icon: const Icon(Icons.add),
                      label: const Text('Create First Tenant'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppStyles.spacingM),
            itemCount: docs.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppStyles.spacingS),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final companyName = (data['companyName'] ?? 'Unnamed Company')
                  .toString();
              final databaseId =
                  (data['firestoreDatabaseId'] ??
                          data['databaseId'] ??
                          '(default)')
                      .toString();
              final isActive = data['isActive'] != false;

              return Container(
                decoration: AppStyles.cardDecoration,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppStyles.spacingM,
                    vertical: AppStyles.spacingS,
                  ),
                  title: Text(
                    companyName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('ID: ${doc.id}\nDatabase: $databaseId'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Switch(
                        value: isActive,
                        onChanged: (value) => _toggleTenantActive(doc, value),
                      ),
                      Text(
                        isActive ? 'Active' : 'Disabled',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                  onTap: () => _openTenantEditor(existing: doc),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
