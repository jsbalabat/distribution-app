import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/user_provider.dart';
import '../services/firestore_service.dart';
import '../services/firestore_tenant.dart';
import '../styles/app_styles.dart';
import '../utils/app_logger.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  Future<void> _createUser() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String role = 'user';
    bool isDisabled = false;

    final shouldCreate = await showDialog<bool>(
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
              title: const Text('Add New User'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppStyles.spacingM),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppStyles.spacingM),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Temporary Password',
                        helperText:
                            'Required for brand-new accounts; optional if the email already exists',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppStyles.spacingM),
                    DropdownButtonFormField<String>(
                      value: role,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'user', child: Text('User')),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          role = value ?? 'user';
                        });
                      },
                    ),
                    const SizedBox(height: AppStyles.spacingS),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Disabled'),
                      value: isDisabled,
                      onChanged: (value) {
                        setDialogState(() {
                          isDisabled = value;
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
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    final name = nameController.text.trim();
    final email = emailController.text.trim().toLowerCase();
    final password = passwordController.text;

    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();

    if (shouldCreate != true) return;

    if (name.isEmpty || email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name and email are required.'),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final currentUser = context.read<UserProvider>().currentUser;
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'adminCreateUserInTenant',
      );
      await callable.call(<String, dynamic>{
        'name': name,
        'email': email,
        'password': password,
        'role': role,
        'isDisabled': isDisabled,
        'actorCompanyIdentifier': currentUser?.companyId,
        'actorDatabaseId': FirestoreTenant.instance.databaseId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User created successfully.'),
          backgroundColor: AppStyles.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to create user',
        error: error,
        stackTrace: stackTrace,
        tag: 'USERS',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create user: $error'),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _editUser(UserModel user) async {
    final currentUser = context.read<UserProvider>().currentUser;
    final isSelf = user.uid == currentUser?.uid;

    final nameController = TextEditingController(text: user.name);
    final emailController = TextEditingController(text: user.email);
    final passwordController = TextEditingController();
    String role = user.role;
    bool isDisabled = user.isDisabled;

    final shouldSave = await showDialog<bool>(
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
              title: const Text('Edit User'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppStyles.spacingM),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppStyles.spacingM),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password (optional)',
                        helperText: 'Leave blank to keep current password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppStyles.spacingM),
                    DropdownButtonFormField<String>(
                      value: role,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'user', child: Text('User')),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      ],
                      onChanged: isSelf
                          ? null
                          : (value) {
                              setDialogState(() {
                                role = value ?? role;
                              });
                            },
                    ),
                    const SizedBox(height: AppStyles.spacingS),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Disabled'),
                      subtitle: isSelf
                          ? const Text('You cannot disable your own account')
                          : null,
                      value: isDisabled,
                      onChanged: isSelf
                          ? null
                          : (value) {
                              setDialogState(() {
                                isDisabled = value;
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

    final name = nameController.text.trim();
    final email = emailController.text.trim().toLowerCase();
    final password = passwordController.text;

    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();

    if (shouldSave != true) return;

    if (name.isEmpty || email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name and email are required.'),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'adminUpdateUserInTenant',
      );
      await callable.call(<String, dynamic>{
        'targetUid': user.uid,
        'name': name,
        'email': email,
        'role': role,
        'isDisabled': isDisabled,
        'password': password,
        'actorCompanyIdentifier': currentUser?.companyId,
        'actorDatabaseId': FirestoreTenant.instance.databaseId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User updated successfully.'),
          backgroundColor: AppStyles.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to update user',
        error: error,
        stackTrace: stackTrace,
        tag: 'USERS',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update user: $error'),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteUser(UserModel user) async {
    final currentUser = context.read<UserProvider>().currentUser;
    if (user.uid == currentUser?.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot delete your own account.'),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyles.borderRadiusMedium),
          ),
          title: const Text('Delete User'),
          content: Text('Delete ${user.email}? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppStyles.errorColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'adminDeleteUserInTenant',
      );
      await callable.call(<String, dynamic>{
        'targetUid': user.uid,
        'actorCompanyIdentifier': currentUser?.companyId,
        'actorDatabaseId': FirestoreTenant.instance.databaseId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User deleted successfully.'),
          backgroundColor: AppStyles.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to delete user',
        error: error,
        stackTrace: stackTrace,
        tag: 'USERS',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete user: $error'),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<UserProvider>().currentUser;

    return Scaffold(
      backgroundColor: AppStyles.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Manage Users', style: AppStyles.appBarTitleStyle),
        backgroundColor: AppStyles.adminPrimaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createUser,
        backgroundColor: AppStyles.adminPrimaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add User'),
      ),
      body: StreamBuilder<List<UserModel>>(
        stream: _firestoreService.getUsersStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data ?? [];
          if (users.isEmpty) {
            return const Center(child: Text('No users found.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppStyles.spacingM),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final isAdmin = user.role == 'admin';
              final isSelf = currentUser?.uid == user.uid;

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: AppStyles.spacingS),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppStyles.borderRadiusMedium,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(AppStyles.spacingS),
                  leading: CircleAvatar(
                    backgroundColor: isAdmin
                        ? AppStyles.adminPrimaryColor
                        : AppStyles.primaryColor,
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    user.name.isNotEmpty ? user.name : 'No Name',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.email),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildStatusChip(
                            text: user.role.toUpperCase(),
                            color: isAdmin
                                ? AppStyles.adminPrimaryColor
                                : Colors.grey,
                          ),
                          _buildStatusChip(
                            text: user.isDisabled ? 'DISABLED' : 'ACTIVE',
                            color: user.isDisabled
                                ? AppStyles.errorColor
                                : AppStyles.successColor,
                          ),
                          if (isSelf)
                            _buildStatusChip(
                              text: 'YOU',
                              color: AppStyles.primaryColor,
                            ),
                        ],
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await _editUser(user);
                        return;
                      }

                      if (value == 'toggle_status') {
                        await _editUser(
                          UserModel(
                            uid: user.uid,
                            email: user.email,
                            name: user.name,
                            role: user.role,
                            companyId: user.companyId,
                            companyName: user.companyName,
                            firestoreDatabaseId: user.firestoreDatabaseId,
                            isDisabled: !user.isDisabled,
                          ),
                        );
                        return;
                      }

                      if (value == 'toggle_role') {
                        await _editUser(
                          UserModel(
                            uid: user.uid,
                            email: user.email,
                            name: user.name,
                            role: isAdmin ? 'user' : 'admin',
                            companyId: user.companyId,
                            companyName: user.companyName,
                            firestoreDatabaseId: user.firestoreDatabaseId,
                            isDisabled: user.isDisabled,
                          ),
                        );
                        return;
                      }

                      if (value == 'delete') {
                        await _deleteUser(user);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 20),
                            SizedBox(width: 8),
                            Text('Edit User'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle_role',
                        enabled: !isSelf,
                        child: Row(
                          children: [
                            Icon(
                              isAdmin
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                              size: 20,
                              color: isAdmin
                                  ? Colors.orange
                                  : AppStyles.successColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isAdmin ? 'Demote to User' : 'Promote to Admin',
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle_status',
                        enabled: !isSelf,
                        child: Row(
                          children: [
                            Icon(
                              user.isDisabled
                                  ? Icons.check_circle_outline
                                  : Icons.block_outlined,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              user.isDisabled ? 'Enable User' : 'Disable User',
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        enabled: !isSelf,
                        child: const Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.red,
                            ),
                            SizedBox(width: 8),
                            Text('Delete User'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusChip({required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
