import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  // String? _error; // General error message from Firebase

  // State variables for individual field errors
  String? _emailError;
  String? _passwordError;

  Future<void> _login() async {
    // Reset previous errors
    setState(() {
      _emailError = null;
      _passwordError = null;
      // _error = null; // Reset general Firebase error
      _loading = true;
    });

    // Basic client-side validation
    bool isValid = true;
    if (_emailController.text.trim().isEmpty) {
      setState(() {
        _emailError = "Email cannot be empty";
      });
      isValid = false;
    } else if (!_emailController.text.contains('@') ||
        !_emailController.text.contains('.')) {
      setState(() {
        _emailError = "Please enter a valid email address";
      });
      isValid = false;
    }

    if (_passwordController.text.isEmpty) {
      setState(() {
        _passwordError = "Password cannot be empty";
      });
      isValid = false;
    }
    // You could add password length validation here if desired
    // else if (_passwordController.text.length < 6) {
    //   setState(() {
    //     _passwordError = "Password must be at least 6 characters";
    //   });
    //   isValid = false;
    // }

    if (!isValid) {
      setState(() {
        _loading = false;
      });
      return; // Stop if client-side validation fails
    }

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted) {
        // Check if the widget is still in the tree
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          // Handle specific Firebase Auth errors and map them to fields if possible
          if (e.code == 'user-not-found' || e.code == 'invalid-email') {
            _emailError = 'Invalid email or user not found.';
          } else if (e.code == 'wrong-password' ||
              e.code == 'invalid-credential') {
            _passwordError = 'Incorrect password.';
          } else {
            // Generic error for other Firebase issues
            // You might want to display this in a more prominent way
            // like the original _error Text widget you had.
            _emailError = 'Login failed. Check your credentials.';
            print(
              'Firebase Auth Error: ${e.message}',
            ); // Log the detailed error
          }
        });
      }
    } catch (e) {
      // Catch any other unexpected errors
      if (mounted) {
        setState(() {
          _emailError = 'An unexpected error occurred. Please try again.';
          print('Unexpected Error: ${e.toString()}');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          // Added SingleChildScrollView for smaller screens
          child: Card(
            margin: const EdgeInsets.all(24),
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              // Wrap with Form widget if using _formKey for validation
              // child: Form(
              //   key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Sales App Login",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: "Email",
                      hintText: "Enter your email",
                      border: const OutlineInputBorder(),
                      errorText: _emailError,
                      // Display email error here
                      prefixIcon: const Icon(Icons.email),
                    ),
                    onChanged: (value) {
                      // Optionally clear error when user starts typing
                      if (_emailError != null) {
                        setState(() {
                          _emailError = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: "Password",
                      hintText: "Enter your password",
                      border: const OutlineInputBorder(),
                      errorText: _passwordError,
                      // Display password error here
                      prefixIcon: const Icon(Icons.lock),
                    ),
                    onChanged: (value) {
                      // Optionally clear error when user starts typing
                      if (_passwordError != null) {
                        setState(() {
                          _passwordError = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // // This was your original general error display.
                  // // You can decide if you still want a general error message
                  // // in addition to field-specific errors.
                  // if (_error != null && _emailError == null && _passwordError == null)
                  //   Padding(
                  //     padding: const EdgeInsets.only(bottom: 8.0),
                  //     child: Text(
                  //       _error!,
                  //       style: const TextStyle(color: Colors.red, fontSize: 14),
                  //       textAlign: TextAlign.center,
                  //     ),
                  //   ),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _login,
                    icon: _loading
                        ? Container(
                            width: 24,
                            height: 24,
                            padding: const EdgeInsets.all(2.0),
                            child: const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : const Icon(Icons.login),
                    label: const Text("Login"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              // ),
            ),
          ),
        ),
      ),
    );
  }
}
