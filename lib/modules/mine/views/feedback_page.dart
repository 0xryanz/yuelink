import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../shared/app_notifier.dart';

/// 原生意见反馈页 — 替代外跳 Telegram。
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _ctrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      AppNotifier.error('请输入反馈内容');
      return;
    }

    setState(() => _submitting = true);
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      try {
        final uri = Uri.parse('https://yue.yuebao.website/api/client/feedback');
        final request = await client.postUrl(uri);
        request.headers.set('Content-Type', 'application/json');
        request.headers.set('Accept', 'application/json');
        request.write(jsonEncode({
          'content': text,
          'contact': _contactCtrl.text.trim(),
        }));
        final response = await request.close();
        await response.drain();
        if (!mounted) return;

        if (response.statusCode >= 200 && response.statusCode < 300) {
          AppNotifier.success('感谢反馈，我们会尽快处理');
          Navigator.of(context).pop();
        } else {
          AppNotifier.error('提交失败，请稍后重试');
        }
      } finally {
        client.close();
      }
    } catch (_) {
      if (mounted) AppNotifier.error('网络错误，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('意见反馈'),
        backgroundColor: isDark ? YLColors.zinc900 : Colors.white,
        foregroundColor: isDark ? Colors.white : YLColors.zinc900,
        elevation: 0,
      ),
      backgroundColor: isDark ? YLColors.zinc950 : YLColors.zinc50,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '描述你遇到的问题或建议',
            style: YLText.label.copyWith(
              color: isDark ? YLColors.zinc300 : YLColors.zinc700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? YLColors.zinc800 : Colors.white,
              borderRadius: BorderRadius.circular(YLRadius.lg),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: TextField(
              controller: _ctrl,
              maxLines: 6,
              maxLength: 500,
              style: YLText.body.copyWith(
                color: isDark ? Colors.white : YLColors.zinc900,
              ),
              decoration: InputDecoration(
                hintText: '请详细描述问题或建议…',
                hintStyle: YLText.body.copyWith(color: YLColors.zinc400),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
                counterStyle: YLText.caption.copyWith(color: YLColors.zinc500),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '联系方式（选填）',
            style: YLText.label.copyWith(
              color: isDark ? YLColors.zinc300 : YLColors.zinc700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? YLColors.zinc800 : Colors.white,
              borderRadius: BorderRadius.circular(YLRadius.lg),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: TextField(
              controller: _contactCtrl,
              style: YLText.body.copyWith(
                color: isDark ? Colors.white : YLColors.zinc900,
              ),
              decoration: InputDecoration(
                hintText: 'Telegram / 邮箱',
                hintStyle: YLText.body.copyWith(color: YLColors.zinc400),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : YLColors.zinc900,
                foregroundColor: isDark ? YLColors.zinc900 : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YLRadius.lg),
                ),
                elevation: 0,
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('提交反馈', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
