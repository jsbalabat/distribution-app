import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart';
import '../styles/app_styles.dart';

class ManageUsersScreen extends StatelessWidget {
  const ManageUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return Scaffold(
      backgroundColor: AppStyles.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Manage Users', style: AppStyles.appBarTitleStyle),
        backgroundColor: AppStyles.adminPrimaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: StreamBuilder<List<UserModel>>(
        stream: firestoreService.getUsersStream(),
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
              final isCurrentUserAdmin = user.role == 'admin';

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
                    backgroundColor: isCurrentUserAdmin
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isCurrentUserAdmin
                              ? AppStyles.adminPrimaryColor.withValues(
                                  alpha: 0.1,
                                )
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isCurrentUserAdmin
                                ? AppStyles.adminPrimaryColor
                                : Colors.grey,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          user.role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isCurrentUserAdmin
                                ? AppStyles.adminPrimaryColor
                                : Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'toggle_role') {
                        final newRole = isCurrentUserAdmin ? 'user' : 'admin';
                        try {
                          await firestoreService.updateUserRole(
                            user.uid,
                            newRole,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Updated ${user.email} role to $newRole',
                              ),
                              backgroundColor: AppStyles.successColor,
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error updating role: $e'),
                              backgroundColor: AppStyles.errorColor,
                            ),
                          );
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'toggle_role',
                        child: Row(
                          children: [
                            Icon(
                              isCurrentUserAdmin
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                              color: isCurrentUserAdmin
                                  ? Colors.orange
                                  : AppStyles.successColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isCurrentUserAdmin
                                  ? 'Demote to User'
                                  : 'Promote to Admin',
                            ),
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
}
