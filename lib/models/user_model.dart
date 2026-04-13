// lib/models/user_model.dart
class UserModel {
  final String uid;
  final String email;
  final String name;
  final String role; // 'admin' or 'user'
  final String companyId;
  final String companyName;
  final String firestoreDatabaseId;
  final bool isDisabled;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.companyId = '',
    this.companyName = '',
    this.firestoreDatabaseId = '(default)',
    this.isDisabled = false,
  });

  factory UserModel.fromMap(Map<String, dynamic> data, String id) {
    return UserModel(
      uid: id,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      role: data['role'] ?? 'user',
      companyId: data['companyId'] ?? '',
      companyName: data['companyName'] ?? '',
      firestoreDatabaseId:
          data['firestoreDatabaseId'] ?? data['databaseId'] ?? '(default)',
      isDisabled: data['isDisabled'] == true || data['disabled'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role,
      'companyId': companyId,
      'companyName': companyName,
      'firestoreDatabaseId': firestoreDatabaseId,
      'isDisabled': isDisabled,
      'disabled': isDisabled,
    };
  }

  bool get isAdmin => role == 'admin';
}
