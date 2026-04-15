import 'dart:io';

import '../infrastructure/datasources/xboard/errors.dart';

/// Maps raw exceptions to user-facing Chinese strings suitable for a
/// snackbar or toast. The caller is expected to append technical detail
/// separately for diagnostics (log file, bug report), not in the UI.
///
/// Keep messages short and actionable — "wifi 没开" is better than
/// "SocketException: Failed host lookup". Do NOT leak stack traces,
/// URLs, tokens, or HTTP status codes to end users.
String friendlyError(Object e) {
  // XBoard business error (HTTP 200 with status:"fail" body).
  if (e is XBoardApiException) {
    final raw = e.message.trim();
    if (raw.isEmpty) {
      if (e.statusCode == 401 || e.statusCode == 403) return '登录已过期，请重新登录';
      if (e.statusCode == 502 || e.statusCode == 503 || e.statusCode == 504) {
        return '服务繁忙，请稍后再试';
      }
      if (e.statusCode == 0) return '无法连接到服务器，请检查网络';
      return '服务出了点问题，请稍后再试';
    }
    // Known Chinese XBoard messages — pass through.
    // Known English default — translate common ones.
    const enToZh = <String, String>{
      'Unauthenticated.': '登录已过期，请重新登录',
      'Too Many Attempts.': '请求过于频繁，请稍后再试',
    };
    return enToZh[raw] ?? raw;
  }

  // Network errors from dart:io
  if (e is SocketException) {
    final msg = e.message.toLowerCase();
    if (msg.contains('failed host lookup') ||
        msg.contains('name or service not known')) {
      return '网络无法解析服务器地址，请检查网络连接';
    }
    if (msg.contains('connection refused')) return '服务器拒绝连接，稍后再试';
    if (msg.contains('no route to host')) return '无法到达服务器，请检查网络';
    return '网络连接失败，请检查 wifi 或移动数据';
  }

  if (e is HandshakeException) {
    return 'TLS 握手失败，可能是中间网络劫持或时间不正确';
  }

  if (e is HttpException) return '请求失败，请稍后再试';

  if (e is FormatException) return '数据格式异常，请重试';

  // TimeoutException — check by type name to avoid depending on dart:async here.
  if (e.runtimeType.toString() == 'TimeoutException') {
    return '请求超时，请检查网络';
  }

  // Unknown — return a short fallback but not the raw stack/type.
  final s = e.toString();
  // Strip "Exception: " prefix that most Dart exceptions start with.
  final trimmed = s.startsWith('Exception: ') ? s.substring(11) : s;
  if (trimmed.length > 80) return '操作失败，请稍后重试';
  return trimmed;
}
