import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../utils/requisition_fields.dart';

class SubmissionsScreen extends StatefulWidget {
  const SubmissionsScreen({super.key});

  @override
  State<SubmissionsScreen> createState() => _SubmissionsScreenState();
}

class _SubmissionsScreenState extends State<SubmissionsScreen> {
  static const int _pageSize = 20;

  final FirestoreService _firestoreService = FirestoreService();
  final List<DocumentSnapshot<Map<String, dynamic>>> _docs = [];

  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isInitialLoading = true;
      _error = null;
      _hasMore = true;
      _lastDoc = null;
      _docs.clear();
    });

    try {
      final snapshot = await _firestoreService.fetchUserSubmissionsPage(
        limit: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        _docs.addAll(snapshot.docs);
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length == _pageSize;
        _isInitialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isInitialLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _lastDoc == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final snapshot = await _firestoreService.fetchUserSubmissionsPage(
        limit: _pageSize,
        startAfter: _lastDoc,
      );

      if (!mounted) return;
      setState(() {
        _docs.addAll(snapshot.docs);
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : _lastDoc;
        _hasMore = snapshot.docs.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Submissions")),
      body: _isInitialLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _docs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadInitial,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _docs.isEmpty
          ? const Center(child: Text("No submissions found."))
          : RefreshIndicator(
              onRefresh: _loadInitial,
              child: ListView.builder(
                itemCount: _docs.length + 1,
                itemBuilder: (context, index) {
                  if (index >= _docs.length) {
                    if (_isLoadingMore) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (_hasMore) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: OutlinedButton(
                          onPressed: _loadMore,
                          child: const Text('Load More'),
                        ),
                      );
                    }

                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'End of submissions',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  final data = _docs[index].data() ?? <String, dynamic>{};
                  final ts = RequisitionFields.timestamp(data);
                  return ListTile(
                    title: Text(RequisitionFields.sorNumber(data)),
                    subtitle: Text(
                      "Customer: ${data['customerName'] ?? 'N/A'}",
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "₱${RequisitionFields.totalAmount(data).toStringAsFixed(2)}",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (ts != null)
                          Text(
                            ts.toLocal().toString().split('.')[0],
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
