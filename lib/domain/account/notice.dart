/// 用户通知/公告模型（对应 XBoard /api/v1/user/notice/fetch）。
class AccountNotice {
  final String title;
  final String content;
  final String? createdAt;

  const AccountNotice({
    required this.title,
    required this.content,
    this.createdAt,
  });

  factory AccountNotice.fromJson(Map<String, dynamic> j) => AccountNotice(
        title: j['title'] as String? ?? '',
        content: j['content'] as String? ?? '',
        createdAt: (j['created_at'] ?? j['updated_at'])?.toString(),
      );
}
