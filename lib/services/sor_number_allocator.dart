import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'firestore_tenant.dart';

/// Builds the human-facing SOR number, e.g. "HDI1-260619-001".
String formatSorNumber(String prefix, DateTime date, int sequence) {
  final dateStr = DateFormat('yyMMdd').format(date);
  return '$prefix-$dateStr-${sequence.toString().padLeft(3, '0')}';
}

/// Assigns SOR numbers at submission time from an atomic per-day counter, so two
/// devices submitting at once (or offline submissions syncing later) never collide.
class SorNumberAllocator {
  SorNumberAllocator._();

  static final SorNumberAllocator instance = SorNumberAllocator._();

  // Fixed company SOR prefix; currently identical across tenants.
  static const String _prefix = 'HDI1';

  /// Claims and returns the next number for [now]'s day. Runs online only — the
  /// transaction needs connectivity, which submission/sync already guarantees.
  Future<String> allocate({DateTime? now}) async {
    final date = now ?? DateTime.now();
    final dateStr = DateFormat('yyMMdd').format(date);
    final firestore = FirestoreTenant.instance.firestore;
    final counterRef = firestore.collection('counters').doc('$_prefix-$dateStr');

    final sequence = await firestore.runTransaction<int>((txn) async {
      final snapshot = await txn.get(counterRef);
      final current = (snapshot.data()?['seq'] as num?)?.toInt() ?? 0;
      final next = current + 1;
      txn.set(counterRef, {
        'seq': next,
        'date': dateStr,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return next;
    });

    return formatSorNumber(_prefix, date, sequence);
  }
}
