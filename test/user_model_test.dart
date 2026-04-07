import 'package:flutter_test/flutter_test.dart';
import 'package:new_test_store/models/user_model.dart';

void main() {
  group('UserModel', () {
    test('uses sensible defaults for partial maps', () {
      final user = UserModel.fromMap({'email': 'admin@example.com'}, 'uid-1');

      expect(user.uid, 'uid-1');
      expect(user.email, 'admin@example.com');
      expect(user.name, '');
      expect(user.role, 'user');
      expect(user.isAdmin, isFalse);
    });

    test('recognizes admin users', () {
      final user = UserModel(
        uid: 'uid-2',
        email: 'owner@example.com',
        name: 'Owner',
        role: 'admin',
      );

      expect(user.isAdmin, isTrue);
    });
  });
}
