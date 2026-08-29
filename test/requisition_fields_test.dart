import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_test_store/utils/requisition_fields.dart';

void main() {
  group('RequisitionFields', () {
    test('prefers sorNumber and totalAmount when present', () {
      final data = {
        'sorNumber': 'SOR-001',
        'totalAmount': 1250.5,
        'userID': 'user-123',
      };

      expect(RequisitionFields.sorNumber(data), 'SOR-001');
      expect(RequisitionFields.totalAmount(data), 1250.5);
      expect(RequisitionFields.userId(data), 'user-123');
    });

    test('falls back to legacy requisition fields', () {
      final data = {
        'sorNo': 'OLD-002',
        'amount': '980.25',
        'uid': 'legacy-user',
      };

      expect(RequisitionFields.sorNumber(data), 'OLD-002');
      expect(RequisitionFields.totalAmount(data), 980.25);
      expect(RequisitionFields.userId(data), 'legacy-user');
    });

    test('parses timestamps from DateTime and Firestore Timestamp', () {
      final now = DateTime(2026, 4, 7, 10, 30);
      final firestoreTimestamp = Timestamp.fromDate(now);

      expect(RequisitionFields.timestamp({'timeStamp': now}), now);
      expect(
        RequisitionFields.timestamp({'timestamp': firestoreTimestamp}),
        now,
      );
    });
  });

  group('RequisitionFields.remarksLine', () {
    test('joins both credit-control remarks', () {
      final data = {'remark1': 'OCL', 'remark2': 'Past Due / Unsecured'};
      expect(RequisitionFields.remarksLine(data), 'OCL, Past Due / Unsecured');
    });

    test('skips a blank or missing remark', () {
      expect(
        RequisitionFields.remarksLine({'remark2': 'Past Due / Unsecured'}),
        'Past Due / Unsecured',
      );
      expect(RequisitionFields.remarksLine({'remark1': 'OCL', 'remark2': '  '}), 'OCL');
    });

    test('returns empty when neither remark is set', () {
      expect(RequisitionFields.remarksLine({}), '');
      expect(RequisitionFields.remarksLine({'remark1': null, 'remark2': null}), '');
    });

    test('ignores the legacy singular remarks field', () {
      // The bug the fix addresses: PDFs used to read `remarks`, which nothing
      // writes; only remark1/remark2 should ever be reflected.
      expect(RequisitionFields.remarksLine({'remarks': 'ignored'}), '');
    });
  });
}
