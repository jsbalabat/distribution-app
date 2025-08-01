import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  Future<void> _submitData(BuildContext context, Map<String, dynamic> formData) async {
    try {
        await FirestoreService().submitSOR(formData);
      Navigator.pushReplacementNamed(context, '/confirmation');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${e.toString()}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> formData =
    ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    return Scaffold(
      appBar: AppBar(title: const Text("Review Submission")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ...formData.entries.map((entry) => ListTile(
              title: Text(entry.key),
              subtitle: Text(entry.value.toString()),
            )),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _submitData(context, formData),
              child: const Text("Submit"),
            ),
          ],
        ),
      ),
    );
  }
}