class ErrorMapper {
  static String mapAuthError(String code) {
    switch (code) {
      case 'invalid-email':
        return 'Invalid email format.';
      case 'user-not-found':
        return 'No account found for this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'user-disabled':
        return 'This account has been disabled. Contact an administrator.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your connection and try again.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  static String mapFirestoreError(String code, {String? action}) {
    final prefix = action == null ? '' : '$action failed: ';
    switch (code) {
      case 'permission-denied':
        return '${prefix}You do not have permission to perform this action.';
      case 'unavailable':
        return '${prefix}Service is temporarily unavailable. Try again shortly.';
      case 'not-found':
        return '${prefix}Requested data was not found.';
      case 'deadline-exceeded':
        return '${prefix}The request timed out. Please retry.';
      case 'resource-exhausted':
        return '${prefix}Quota exceeded. Please try again later.';
      default:
        return '${prefix}A database error occurred. Please try again.';
    }
  }
}
