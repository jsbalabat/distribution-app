import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/user_provider.dart';
import '../services/firestore_service.dart';
import '../services/firestore_tenant.dart';
import '../styles/app_styles.dart';
import '../utils/admin_navigation.dart';
import '../utils/app_logger.dart';
import '../widgets/admin_desktop_shell.dart';
import '../widgets/admin_screen_guard.dart';

enum UserListFilter { all, admins, users, active, disabled }

enum UserSortOption { nameAsc, nameDesc, emailAsc, role }

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  UserListFilter _activeFilter = UserListFilter.all;
  UserSortOption _sortOption = UserSortOption.nameAsc;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
                      initialValue: role,
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

    if (!mounted) return;
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
                      initialValue: role,
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

  Future<void> _toggleUserStatus(UserModel user) async {
    final currentUser = context.read<UserProvider>().currentUser;
    final isSelf = user.uid == currentUser?.uid;

    if (isSelf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot disable or enable your own account.'),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final nextDisabledValue = !user.isDisabled;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'adminUpdateUserInTenant',
      );
      await callable.call(<String, dynamic>{
        'targetUid': user.uid,
        'name': user.name,
        'email': user.email,
        'role': user.role,
        'isDisabled': nextDisabledValue,
        'password': '',
        'actorCompanyIdentifier': currentUser?.companyId,
        'actorDatabaseId': FirestoreTenant.instance.databaseId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextDisabledValue
                ? 'User has been disabled.'
                : 'User has been enabled.',
          ),
          backgroundColor: AppStyles.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to toggle user status',
        error: error,
        stackTrace: stackTrace,
        tag: 'USERS',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update user status: $error'),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<UserModel> _applyFiltersAndSorting(List<UserModel> users) {
    final query = _searchQuery.trim().toLowerCase();

    final filtered = users.where((user) {
      final matchesSearch =
          query.isEmpty ||
          user.name.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query) ||
          user.role.toLowerCase().contains(query);

      if (!matchesSearch) {
        return false;
      }

      switch (_activeFilter) {
        case UserListFilter.admins:
          return user.role == 'admin';
        case UserListFilter.users:
          return user.role != 'admin';
        case UserListFilter.active:
          return !user.isDisabled;
        case UserListFilter.disabled:
          return user.isDisabled;
        case UserListFilter.all:
          return true;
      }
    }).toList();

    filtered.sort((a, b) {
      switch (_sortOption) {
        case UserSortOption.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case UserSortOption.nameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case UserSortOption.emailAsc:
          return a.email.toLowerCase().compareTo(b.email.toLowerCase());
        case UserSortOption.role:
          return a.role.toLowerCase().compareTo(b.role.toLowerCase());
      }
    });

    return filtered;
  }

  Widget _buildSummaryChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppStyles.borderRadiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 15,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppStyles.textSecondaryColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateDesktop(AdminShellSection section) {
    navigateToAdminSection(
      context,
      section,
      currentSection: AdminShellSection.users,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<UserProvider>().currentUser;
    final isDesktop =
        MediaQuery.of(context).size.width >=
        AdminDesktopShell.desktopBreakpoint;

    final body = StreamBuilder<List<UserModel>>(
      stream: _firestoreService.getUsersStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppStyles.spacingL),
              child: Container(
                decoration: AppStyles.cardDecoration,
                padding: const EdgeInsets.all(AppStyles.spacingL),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 36,
                      color: AppStyles.errorColor,
                    ),
                    const SizedBox(height: AppStyles.spacingS),
                    const Text(
                      'Unable to load users',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppStyles.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: AppStyles.spacingS),
                Text('Loading users...'),
              ],
            ),
          );
        }

        final users = snapshot.data ?? [];
        final adminCount = users.where((u) => u.role == 'admin').length;
        final disabledCount = users.where((u) => u.isDisabled).length;

        final visibleUsers = _applyFiltersAndSorting(users);

        if (users.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppStyles.spacingL),
              child: Container(
                decoration: AppStyles.cardDecoration,
                padding: const EdgeInsets.all(AppStyles.spacingL),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.group_outlined,
                      size: 44,
                      color: AppStyles.textLightColor,
                    ),
                    SizedBox(height: AppStyles.spacingS),
                    Text(
                      'No users found in this company yet.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tap Add User to create or attach a user account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppStyles.textSecondaryColor),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(AppStyles.spacingM),
          children: [
            Container(
              decoration: AppStyles.cardDecoration,
              padding: const EdgeInsets.all(AppStyles.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Directory Overview',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: AppStyles.spacingS),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildSummaryChip(
                        label: 'Total Users',
                        value: '${users.length}',
                        color: AppStyles.primaryColor,
                      ),
                      _buildSummaryChip(
                        label: 'Admins',
                        value: '$adminCount',
                        color: AppStyles.adminPrimaryColor,
                      ),
                      _buildSummaryChip(
                        label: 'Disabled',
                        value: '$disabledCount',
                        color: AppStyles.errorColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppStyles.spacingM),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      hintText: 'Search name, email, or role',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppStyles.borderRadiusMedium,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppStyles.spacingS),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _activeFilter == UserListFilter.all,
                          onSelected: (_) => setState(() {
                            _activeFilter = UserListFilter.all;
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('Admins'),
                          selected: _activeFilter == UserListFilter.admins,
                          onSelected: (_) => setState(() {
                            _activeFilter = UserListFilter.admins;
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('Users'),
                          selected: _activeFilter == UserListFilter.users,
                          onSelected: (_) => setState(() {
                            _activeFilter = UserListFilter.users;
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('Active'),
                          selected: _activeFilter == UserListFilter.active,
                          onSelected: (_) => setState(() {
                            _activeFilter = UserListFilter.active;
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('Disabled'),
                          selected: _activeFilter == UserListFilter.disabled,
                          onSelected: (_) => setState(() {
                            _activeFilter = UserListFilter.disabled;
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppStyles.spacingS),
                  Row(
                    children: [
                      const Text(
                        'Sort by:',
                        style: TextStyle(
                          color: AppStyles.textSecondaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<UserSortOption>(
                        value: _sortOption,
                        underline: const SizedBox.shrink(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _sortOption = value;
                          });
                        },
                        items: const [
                          DropdownMenuItem(
                            value: UserSortOption.nameAsc,
                            child: Text('Name (A-Z)'),
                          ),
                          DropdownMenuItem(
                            value: UserSortOption.nameDesc,
                            child: Text('Name (Z-A)'),
                          ),
                          DropdownMenuItem(
                            value: UserSortOption.emailAsc,
                            child: Text('Email'),
                          ),
                          DropdownMenuItem(
                            value: UserSortOption.role,
                            child: Text('Role'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppStyles.spacingM),
            if (visibleUsers.isEmpty)
              Container(
                decoration: AppStyles.cardDecoration,
                padding: const EdgeInsets.all(AppStyles.spacingL),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.filter_alt_off_outlined,
                      size: 36,
                      color: AppStyles.textLightColor,
                    ),
                    SizedBox(height: AppStyles.spacingS),
                    Text(
                      'No users match your filters.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )
            else
              ...visibleUsers.map((user) {
                final isAdmin = user.role == 'admin';
                final isSelf = currentUser?.uid == user.uid;

                return Padding(
                  padding: const EdgeInsets.only(bottom: AppStyles.spacingS),
                  child: Card(
                    elevation: 2,
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
                          user.name.isNotEmpty
                              ? user.name[0].toUpperCase()
                              : '?',
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
                            await _toggleUserStatus(user);
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
                                  isAdmin
                                      ? 'Demote to User'
                                      : 'Promote to Admin',
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
                                  user.isDisabled
                                      ? 'Enable User'
                                      : 'Disable User',
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
                  ),
                );
              }),
          ],
        );
      },
    );

    final screen = isDesktop
        ? AdminDesktopShell(
            title: 'Manage Users',
            selectedSection: AdminShellSection.users,
            onNavigate: _navigateDesktop,
            actions: [
              IconButton(
                onPressed: _createUser,
                icon: const Icon(
                  Icons.person_add_alt_1_outlined,
                  color: Colors.white,
                ),
                tooltip: 'Add User',
              ),
            ],
            content: body,
          )
        : Scaffold(
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
            body: body,
          );

    return AdminScreenGuard(title: 'Manage Users', child: screen);
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
