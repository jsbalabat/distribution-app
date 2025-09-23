// lib/screens/auth_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../utils/app_styles.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    // Clean up controllers
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
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

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      await userProvider.signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      // Check if widget is still mounted before setting state
      if (!mounted) return;

      // If we reach here, authentication was successful
      // The Consumer in main.dart will handle navigation
    } catch (e) {
      // Check if widget is still mounted before setting state
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
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

  void _switchAuthMode() {
    if (!mounted) return;

    setState(() {
      _isLogin = !_isLogin;
      _errorMessage = '';
    });
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

                      // Auth Mode Title
                      Text(
                        _isLogin ? 'Sign In' : 'Create Account',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Name field (only for sign up)
                      if (!_isLogin) ...[
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

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
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage,
                                  style: TextStyle(color: Colors.red[700]),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
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
                              : Text(
                                  _isLogin ? 'Sign In' : 'Create Account',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Switch auth mode
                      TextButton(
                        onPressed: _isLoading ? null : _switchAuthMode,
                        child: Text(
                          _isLogin
                              ? "Don't have an account? Sign Up"
                              : "Already have an account? Sign In",
                          style: TextStyle(color: AppStyles.primaryColor),
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
