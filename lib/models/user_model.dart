// lib/models/user_model.dart
class UserModel {
  final String uid;
  final String email;
  final String name;
  final String role; // 'admin' or 'user'

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
  });

  factory UserModel.fromMap(Map<String, dynamic> data, String id) {
    return UserModel(
      uid: id,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      role: data['role'] ?? 'user',
    );
  }

  Map<String, dynamic> toMap() {
    return {'email': email, 'name': name, 'role': role};
  }

  bool get isAdmin => role == 'admin';
}
