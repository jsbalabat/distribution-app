/// The two credit-control remark flags shown on a requisition.
class RemarkEvaluation {
  /// 'OCL' when this order pushes the customer past their credit limit.
  final String? remark1;

  /// 'Past Due / Unsecured' when the customer carries aged or unsecured debt.
  final String? remark2;

  const RemarkEvaluation({this.remark1, this.remark2});
}

/// Derives the credit-control remarks from a customer's receivable position.
/// Kept pure so it can run server-authoritatively at submit/sync time against
/// current account-receivable data rather than a possibly-stale offline snapshot.
class RemarkEvaluator {
  static RemarkEvaluation evaluate({
    required double creditLimit,
    required double amountDue,
    required double over30Days,
    required double unsecuredFunds,
    required double orderTotal,
  }) {
    final projectedDue = amountDue + orderTotal;
    final remark1 = projectedDue > creditLimit ? 'OCL' : null;
    final remark2 = (over30Days > 0 || unsecuredFunds > 0)
        ? 'Past Due / Unsecured'
        : null;
    return RemarkEvaluation(remark1: remark1, remark2: remark2);
  }
}
