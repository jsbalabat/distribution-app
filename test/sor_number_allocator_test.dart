import 'package:flutter_test/flutter_test.dart';
import 'package:new_test_store/services/sor_number_allocator.dart';

void main() {
  group('formatSorNumber', () {
    test('zero-pads the daily sequence to three digits', () {
      expect(formatSorNumber('HDI1', DateTime(2026, 6, 19), 1), 'HDI1-260619-001');
      expect(formatSorNumber('HDI1', DateTime(2026, 6, 19), 42), 'HDI1-260619-042');
    });

    test('keeps sequences past 999 intact', () {
      expect(
        formatSorNumber('HDI1', DateTime(2026, 6, 19), 1000),
        'HDI1-260619-1000',
      );
    });
  });
}
