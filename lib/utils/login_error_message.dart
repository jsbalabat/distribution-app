String toLoginFailureMessage(Object error) {
  final raw = error.toString().replaceFirst('Exception: ', '').trim();
  final lower = raw.toLowerCase();

  if (lower.contains('unknown company identifier')) {
    return 'Login failed: the company identifier is not recognized.';
  }
  if (lower.contains('company is currently inactive')) {
    return 'Login failed: this company account is currently inactive.';
  }
  if (lower.contains('missing a firestore database mapping')) {
    return 'Login failed: this company is not fully configured yet. Contact support.';
  }
  if (lower.contains('not assigned to this company')) {
    return 'Login failed: your account is not assigned to this company.';
  }
  if (lower.contains('incorrect email or password')) {
    return 'Login failed: incorrect email or password.';
  }
  if (lower.contains('no account found for this email')) {
    return 'Login failed: no account exists for this email.';
  }
  if (lower.contains('account has been disabled')) {
    return 'Login failed: this account is disabled. Contact an administrator.';
  }
  if (lower.contains('too many attempts')) {
    return 'Login failed: too many attempts. Please wait and try again.';
  }
  if (lower.contains('network error')) {
    return 'Login failed: network error. Check your connection and retry.';
  }
  if (lower.contains('permission') || lower.contains('rules denied access')) {
    return 'Login failed: access to company data was denied. Contact your admin.';
  }

  return raw.isEmpty ? 'Login failed. Please try again.' : 'Login failed: $raw';
}
