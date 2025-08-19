import 'package:flutter/material.dart';

class ConfirmationScreen extends StatelessWidget {
  const ConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Submission Complete")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 80,
              color: Colors.green,
            ),
            const SizedBox(height: 20),
            const Text(
              "Your sales requisition was submitted successfully!",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.dashboard),
              label: const Text("Back to Dashboard"),
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                context,
                '/dashboard',
                (_) => false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
