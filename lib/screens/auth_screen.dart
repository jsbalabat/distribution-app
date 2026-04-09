// lib/screens/auth_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../styles/app_styles.dart';
import '../utils/app_logger.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _companyIdentifierController = TextEditingController();

  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _companyIdentifierController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Check if widget is still mounted before setting state
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    AppLogger.info(
      'UI login submit started for company=${_companyIdentifierController.text.trim().toLowerCase()}',
      tag: 'AUTH_UI',
    );

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      await userProvider.signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        companyIdentifier: _companyIdentifierController.text.trim(),
      );

      // Check if widget is still mounted before setting state
      if (!mounted) return;

      // Authentication is successful here
      // The Consumer in main.dart will handle navigation
      AppLogger.info('UI login submit succeeded', tag: 'AUTH_UI');
    } catch (e) {
      // Check if widget is still mounted before setting state
      if (!mounted) return;

      AppLogger.error('UI login submit failed', error: e, tag: 'AUTH_UI');

      setState(() {
        final raw = e.toString();
        _errorMessage = raw.startsWith('Exception: ')
            ? raw.substring('Exception: '.length)
            : raw;
      });
    } finally {
      // Check if widget is still mounted before setting state
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo or App Title
                      Icon(
                        Icons.store,
                        size: 64,
                        color: AppStyles.primaryColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'New Test Store',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppStyles.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 32),

                      const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Company identifier selector
                      TextFormField(
                        controller: _companyIdentifierController,
                        decoration: InputDecoration(
                          labelText: 'Company Identifier',
                          prefixIcon: const Icon(Icons.account_tree_outlined),
                          helperText:
                              'Enter your company identifier (for example: acme, northstar, company-a).',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) {
                            return 'Please enter your company identifier';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Email field
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.email),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!value.contains('@')) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Password field
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Error message
                      if (_errorMessage.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(AppStyles.paddingSmall),
                          decoration: BoxDecoration(
                            color: AppStyles.errorColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                              AppStyles.borderRadiusMedium,
                            ),
                            border: Border.all(
                              color: AppStyles.errorColor.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: AppStyles.errorColor,
                              ),
                              const SizedBox(width: AppStyles.spacingS),
                              Expanded(
                                child: Text(
                                  _errorMessage,
                                  style: TextStyle(color: AppStyles.errorColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppStyles.spacingM),
                      ],

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppStyles.primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
