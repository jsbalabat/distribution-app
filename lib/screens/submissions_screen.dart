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
  String _searchQuery = '';

  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  bool _isVisibleSubmission(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return data['isDeleted'] != true;
  }

  Future<_SubmissionPageResult> _fetchVisiblePage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    final visibleDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor = startAfter;
    var hasMore = true;

    while (visibleDocs.length < _pageSize && hasMore) {
      final snapshot = await _firestoreService.fetchUserSubmissionsPage(
        limit: _pageSize,
        startAfter: cursor,
      );

      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      final pageVisibleDocs = snapshot.docs
          .where(_isVisibleSubmission)
          .toList();
      visibleDocs.addAll(pageVisibleDocs);
      cursor = snapshot.docs.last;
      hasMore = snapshot.docs.length == _pageSize;
    }

    if (visibleDocs.length > _pageSize) {
      visibleDocs.removeRange(_pageSize, visibleDocs.length);
    }

    return _SubmissionPageResult(
      docs: visibleDocs,
      lastDoc: cursor,
      hasMore: hasMore,
    );
  }

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
      final page = await _fetchVisiblePage(
        startAfter: null,
      );

      if (!mounted) return;
      setState(() {
        _docs.addAll(page.docs);
        _lastDoc = page.lastDoc;
        _hasMore = page.hasMore;
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
      final page = await _fetchVisiblePage(
        startAfter: _lastDoc,
      );

      if (!mounted) return;
      setState(() {
        _docs.addAll(page.docs);
        _lastDoc = page.lastDoc ?? _lastDoc;
        _hasMore = page.hasMore;
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
    final filteredDocs = _docs.where((doc) {
      final data = doc.data() ?? <String, dynamic>{};
      if (_searchQuery.isEmpty) return true;

      final q = _searchQuery.toLowerCase();
      final sor = RequisitionFields.sorNumber(data).toLowerCase();
      final customer = (data['customerName'] ?? '').toString().toLowerCase();
      final account = (data['accountNumber'] ?? '').toString().toLowerCase();

      return sor.contains(q) || customer.contains(q) || account.contains(q);
    }).toList();

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
                itemCount: filteredDocs.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search by SOR, customer, or account',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value.trim();
                          });
                        },
                      ),
                    );
                  }

                  final dataIndex = index - 1;
                  if (dataIndex >= filteredDocs.length) {
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

                  final data =
                      filteredDocs[dataIndex].data() ?? <String, dynamic>{};
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

class _SubmissionPageResult {
  _SubmissionPageResult({
    required this.docs,
    required this.lastDoc,
    required this.hasMore,
  });

  final List<DocumentSnapshot<Map<String, dynamic>>> docs;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;
}
