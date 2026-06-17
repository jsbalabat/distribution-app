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

  // Canonical emailStatus first, then the legacy autoEmailStatus both are written
  // during the field transition; returns a trimmed, lower-cased value.
  static String emailStatus(Map<String, dynamic> data) {
    return (data['emailStatus'] ?? data['autoEmailStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
  }

  static String approvalRoute(Map<String, dynamic> data) {
    return (data['approvalRoute'] ?? '').toString().trim().toLowerCase();
  }

  static List<String> approvalReasons(Map<String, dynamic> data) {
    final value = data['approvalReasons'];
    if (value is List) {
      return value.map((reason) => reason.toString()).toList();
    }
    return const [];
  }

  static bool isDeleted(Map<String, dynamic> data) {
    return data['isDeleted'] == true;
  }
}
