/// 账户快捷操作链接（来自 YueLink Checkin API）。
///
/// GET https://yue.yuebao.website/api/client/account/actions  (无需 token)
class AccountActions {
  final String renewUrl;
  final String feedbackUrl;
  final String telegramGroupUrl;
  final String statusPageUrl;

  const AccountActions({
    required this.renewUrl,
    required this.feedbackUrl,
    required this.telegramGroupUrl,
    required this.statusPageUrl,
  });

  factory AccountActions.fromJson(Map<String, dynamic> json) {
    return AccountActions(
      renewUrl: json['renew_url'] as String? ?? 'https://yue.to/#/plan',
      feedbackUrl: json['feedback_url'] as String? ?? 'https://t.me/yuetong_support',
      telegramGroupUrl: json['telegram_group_url'] as String? ?? 'https://t.me/yuetong_group',
      statusPageUrl: json['status_page_url'] as String? ?? 'https://status.yue.to',
    );
  }

  /// 接口不可用时的兜底数据，保证快捷操作按钮始终可点。
  static const AccountActions fallback = AccountActions(
    renewUrl: 'https://yue.to/#/plan',
    feedbackUrl: 'https://t.me/yuetong_support',
    telegramGroupUrl: 'https://t.me/yuetong_group',
    statusPageUrl: 'https://status.yue.to',
  );
}
