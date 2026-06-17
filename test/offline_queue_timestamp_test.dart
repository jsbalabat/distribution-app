import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:new_test_store/models/offline_sync_adapters.dart';
import 'package:new_test_store/models/offline_sync_contract.dart';
import 'package:new_test_store/models/queued_sales_requisition.dart';

/// Guards the offline write path against the Hive "unknown type: Timestamp"
/// failure: SOR form payloads carry Firestore Timestamps, and they must survive
/// the encrypted queue as real Timestamps so the sync worker can re-submit them.
void main() {
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('hive_timestamp_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(QueuedSalesRequisitionAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(OfflineSorStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(OfflineErrorCategoryAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(TimestampAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('SOR payload with Firestore Timestamps survives a Hive round-trip', () async {
    final invoiceDate = Timestamp.fromDate(DateTime(2026, 6, 17, 9, 30));
    final queuedAt = Timestamp.fromDate(DateTime(2026, 6, 17, 9, 31, 45));
    final box = await Hive.openBox<QueuedSalesRequisition>('round_trip_box');

    final queued = QueuedSalesRequisition(
      clientGeneratedId: 'offline-test-1',
      tenantDatabaseId: 'tenant-a',
      userId: 'user-1',
      correlationId: 'corr-1',
      status: OfflineSorStatus.pendingSync,
      sorDraftPayload: {
        'customerName': 'Acme Feeds',
        'invoiceDate': invoiceDate,
        'queuedAt': queuedAt,
      },
    );

    await box.put(queued.clientGeneratedId, queued);
    final read = box.get(queued.clientGeneratedId);

    expect(read, isNotNull);
    final readInvoice = read!.sorDraftPayload['invoiceDate'];
    final readQueuedAt = read.sorDraftPayload['queuedAt'];
    // Type must survive, not just the value — the sync worker writes these
    // back to Firestore expecting Timestamps.
    expect(readInvoice, isA<Timestamp>());
    expect(readInvoice, equals(invoiceDate));
    expect(readQueuedAt, isA<Timestamp>());
    expect(readQueuedAt, equals(queuedAt));

    await box.close();
  });
}
