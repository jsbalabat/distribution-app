import 'package:flutter_test/flutter_test.dart';
import 'package:new_test_store/utils/remark_evaluator.dart';

void main() {
  group('RemarkEvaluator', () {
    test('flags OCL when the order pushes past the credit limit', () {
      final result = RemarkEvaluator.evaluate(
        creditLimit: 1000,
        amountDue: 800,
        over30Days: 0,
        unsecuredFunds: 0,
        orderTotal: 300,
      );
      expect(result.remark1, 'OCL');
      expect(result.remark2, isNull);
    });

    test('no OCL when the projected balance stays within the limit', () {
      final result = RemarkEvaluator.evaluate(
        creditLimit: 1000,
        amountDue: 200,
        over30Days: 0,
        unsecuredFunds: 0,
        orderTotal: 300,
      );
      expect(result.remark1, isNull);
    });

    test('flags Past Due / Unsecured on aged debt', () {
      final result = RemarkEvaluator.evaluate(
        creditLimit: 1000,
        amountDue: 0,
        over30Days: 50,
        unsecuredFunds: 0,
        orderTotal: 0,
      );
      expect(result.remark2, 'Past Due / Unsecured');
    });

    test('flags Past Due / Unsecured on unsecured funds', () {
      final result = RemarkEvaluator.evaluate(
        creditLimit: 1000,
        amountDue: 0,
        over30Days: 0,
        unsecuredFunds: 25,
        orderTotal: 0,
      );
      expect(result.remark2, 'Past Due / Unsecured');
    });

    test('clean account yields no remarks', () {
      final result = RemarkEvaluator.evaluate(
        creditLimit: 1000,
        amountDue: 100,
        over30Days: 0,
        unsecuredFunds: 0,
        orderTotal: 100,
      );
      expect(result.remark1, isNull);
      expect(result.remark2, isNull);
    });
  });
}
