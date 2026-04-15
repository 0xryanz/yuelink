import 'package:flutter/material.dart';

import '../../../domain/models/connection.dart';
import '../../../i18n/app_strings.dart';
import '../../../theme.dart';
import 'detail_row.dart';

class ConnectionDetailSheet extends StatelessWidget {
  final ActiveConnection connection;
  const ConnectionDetailSheet({super.key, required this.connection});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: isDark ? YLColors.zinc900 : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(YLRadius.xl)),
          boxShadow: YLShadow.overlay(context),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? YLColors.zinc700 : YLColors.zinc300,
                  borderRadius: BorderRadius.circular(YLRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(s.connectionDetailTitle, style: YLText.titleLarge),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? YLColors.zinc950 : YLColors.zinc50,
                borderRadius: BorderRadius.circular(YLRadius.lg),
                border: Border.all(color: isDark ? YLColors.zinc800 : YLColors.zinc200),
              ),
              child: Column(
                children: [
                  DetailRow(s.detailTarget, connection.target),
                  const Divider(height: 24),
                  DetailRow(s.detailProtocol, '${connection.network.toUpperCase()} / ${connection.type}'),
                  const Divider(height: 24),
                  DetailRow(s.detailSource, '${connection.sourceIp}:${connection.sourcePort}'),
                  if (connection.destinationIp.isNotEmpty) ...[
                    const Divider(height: 24),
                    DetailRow(s.detailTargetIp, '${connection.destinationIp}:${connection.destinationPort}'),
                  ],
                  const Divider(height: 24),
                  DetailRow(s.detailProxyChain, connection.chains.join(' → ')),
                  const Divider(height: 24),
                  DetailRow(
                    s.detailRule,
                    connection.rule + (connection.rulePayload.isNotEmpty ? ' (${connection.rulePayload})' : ''),
                  ),
                  if (connection.processName.isNotEmpty) ...[
                    const Divider(height: 24),
                    DetailRow(s.detailProcess, connection.processName),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? YLColors.zinc950 : YLColors.zinc50,
                borderRadius: BorderRadius.circular(YLRadius.lg),
                border: Border.all(color: isDark ? YLColors.zinc800 : YLColors.zinc200),
              ),
              child: Column(
                children: [
                  DetailRow(s.detailDuration, connection.durationText),
                  const Divider(height: 24),
                  DetailRow(s.detailDownload, _fmtBytes(connection.download)),
                  const Divider(height: 24),
                  DetailRow(s.detailUpload, _fmtBytes(connection.upload)),
                  const Divider(height: 24),
                  DetailRow(s.detailConnectTime, _formatTime(connection.start)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatTime(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }
}
