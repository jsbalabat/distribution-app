import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/firestore_tenant.dart';
import '../styles/app_styles.dart';

class AuditLogsScreen extends StatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  String _query = '';
  String _selectedAction = 'all';
  String _selectedEntityType = 'all';

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final data = doc.data();
      final action = (data['action'] ?? '').toString().toLowerCase();
      final entityType = (data['entityType'] ?? '').toString().toLowerCase();
      final actorEmail = (data['actorEmail'] ?? '').toString().toLowerCase();
      final entityId = (data['entityId'] ?? '').toString().toLowerCase();

      final matchesAction =
          _selectedAction == 'all' || action == _selectedAction;
      final matchesEntity =
          _selectedEntityType == 'all' || entityType == _selectedEntityType;

      if (_query.isEmpty) {
        return matchesAction && matchesEntity;
      }

      final q = _query.toLowerCase();
      final matchesQuery =
          action.contains(q) ||
          entityType.contains(q) ||
          actorEmail.contains(q) ||
          entityId.contains(q);

      return matchesAction && matchesEntity && matchesQuery;
    }).toList();
  }

  String _escapeCsvField(Object? value) {
    final text = value?.toString() ?? '';
    if (text.contains(',') || text.contains('"') || text.contains('\n')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  Future<void> _exportFilteredLogs() async {
    try {
      final snapshot = await FirestoreTenant.instance.firestore
          .collection('auditLogs')
          .orderBy('timestamp', descending: true)
          .limit(300)
          .get();

      final filtered = _applyFilters(snapshot.docs);

      if (filtered.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No filtered audit logs to export.')),
        );
        return;
      }

      final buffer = StringBuffer();
      buffer.writeln(
        'timestamp,action,entityType,entityId,actorEmail,actorId,details',
      );

      for (final doc in filtered) {
        final data = doc.data();
        final timestampValue = data['timestamp'];
        final timestamp = timestampValue is Timestamp
            ? DateFormat('y-MM-dd HH:mm:ss').format(timestampValue.toDate())
            : '';
        final details =
            (data['details'] as Map<String, dynamic>?) ?? <String, dynamic>{};

        buffer.writeln(
          [
            timestamp,
            data['action'],
            data['entityType'],
            data['entityId'],
            data['actorEmail'],
            data['actorId'],
            jsonEncode(details),
          ].map(_escapeCsvField).join(','),
        );
      }

      await Clipboard.setData(ClipboardData(text: buffer.toString()));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Copied ${filtered.length} audit logs as CSV to clipboard.',
          ),
          backgroundColor: AppStyles.successColor,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export audit logs: $error'),
          backgroundColor: AppStyles.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyles.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Audit Logs', style: AppStyles.appBarTitleStyle),
        backgroundColor: AppStyles.adminPrimaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _exportFilteredLogs,
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Copy CSV',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search action, entity, actor email, or entity id',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value.trim();
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedAction,
                    decoration: const InputDecoration(labelText: 'Action'),
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('All Actions'),
                      ),
                      DropdownMenuItem(value: 'create', child: Text('Create')),
                      DropdownMenuItem(value: 'update', child: Text('Update')),
                      DropdownMenuItem(value: 'delete', child: Text('Delete')),
                      DropdownMenuItem(
                        value: 'updaterole',
                        child: Text('Update Role'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedAction = value ?? 'all';
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedEntityType,
                    decoration: const InputDecoration(labelText: 'Entity'),
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('All Entities'),
                      ),
                      DropdownMenuItem(
                        value: 'salesrequisition',
                        child: Text('Sales Requisition'),
                      ),
                      DropdownMenuItem(
                        value: 'inventory',
                        child: Text('Inventory'),
                      ),
                      DropdownMenuItem(value: 'user', child: Text('User')),
                      DropdownMenuItem(
                        value: 'settings',
                        child: Text('Settings'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedEntityType = value ?? 'all';
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreTenant.instance.firestore
                  .collection('auditLogs')
                  .orderBy('timestamp', descending: true)
                  .limit(300)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs =
                    snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                final filtered = _applyFilters(docs);

                if (filtered.isEmpty) {
                  return const Center(child: Text('No audit logs found.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final data = filtered[index].data();
                    final action = (data['action'] ?? 'unknown').toString();
                    final entityType = (data['entityType'] ?? 'unknown')
                        .toString();
                    final actorEmail = (data['actorEmail'] ?? 'unknown')
                        .toString();
                    final entityId = (data['entityId'] ?? '').toString();
                    final details =
                        (data['details'] as Map<String, dynamic>?) ??
                        <String, dynamic>{};
                    final ts = data['timestamp'];
                    final timestamp = ts is Timestamp
                        ? DateFormat('yMMMd HH:mm:ss').format(ts.toDate())
                        : 'pending...';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          12,
                        ),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: AppStyles.primaryColor.withValues(
                            alpha: 0.08,
                          ),
                          child: Icon(
                            _iconForAction(action),
                            color: AppStyles.primaryColor,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          '${action.toUpperCase()} • $entityType',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '$actorEmail\n$timestamp',
                          style: const TextStyle(fontSize: 12),
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Entity ID: ${entityId.isEmpty ? 'N/A' : entityId}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Details',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              details.isEmpty
                                  ? 'No additional details.'
                                  : details.entries
                                        .map((e) => '${e.key}: ${e.value}')
                                        .join('\n'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForAction(String action) {
    switch (action.toLowerCase()) {
      case 'create':
        return Icons.add_circle_outline;
      case 'update':
      case 'updaterole':
        return Icons.edit_outlined;
      case 'delete':
        return Icons.delete_outline;
      default:
        return Icons.info_outline;
    }
  }
}
