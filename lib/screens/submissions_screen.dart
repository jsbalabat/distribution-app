import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class SubmissionsScreen extends StatelessWidget {
  const SubmissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Submissions")),
      body: StreamBuilder(
        stream: FirestoreService().getUserSubmissions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text("No submissions found."));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return ListTile(
                title: Text(data['sorNo'] ?? 'No SOR'),
                subtitle: Text("Customer: ${data['customerName'] ?? 'N/A'}"),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("₱${data['amount'] ?? '0'}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (data['timestamp'] != null)
                      Text(
                        (data['timestamp'] as Timestamp).toDate().toLocal().toString().split('.')[0],
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}