class RequisitionFields {
  static String sorNumber(Map<String, dynamic> data) {
    final value = (data['sorNumber'] ?? data['sorNo'] ?? '').toString();
    return value.isNotEmpty ? value : 'N/A';
  }

  static double totalAmount(Map<String, dynamic> data) {
    final value = data['totalAmount'] ?? data['amount'] ?? 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  static DateTime? timestamp(Map<String, dynamic> data) {
    final value = data['timeStamp'] ?? data['timestamp'] ?? data['createdAt'];
    if (value is DateTime) {
      return value;
    }
    if (value != null && value.runtimeType.toString() == 'Timestamp') {
      return (value as dynamic).toDate() as DateTime;
    }
    return null;
  }

  static String userId(Map<String, dynamic> data) {
    final value = (data['userID'] ?? data['uid'] ?? '').toString();
    return value;
  }
}
