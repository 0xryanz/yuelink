/// Result of a check-in operation.
class CheckinResult {
  /// "traffic" or "balance"
  final String type;

  /// Raw amount: bytes for traffic, 分 (cents) for balance
  final int amount;

  /// Human-readable amount text (e.g. "10GB", "0.6元")
  final String amountText;

  /// Whether the user has already checked in today
  final bool alreadyChecked;

  const CheckinResult({
    required this.type,
    required this.amount,
    required this.amountText,
    required this.alreadyChecked,
  });

  factory CheckinResult.fromJson(Map<String, dynamic> json) {
    return CheckinResult(
      type: json['type'] as String? ?? 'traffic',
      amount: _toInt(json['amount']) ?? 0,
      amountText: json['amount_text'] as String? ?? '',
      alreadyChecked: json['already_checked'] == true,
    );
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return null;
  }
}
