import 'package:flutter/material.dart';

import '../../../domain/logs/log_entry.dart';

class LogTile extends StatelessWidget {
  final LogEntry entry;
  final bool isDesktop;
  const LogTile({super.key, required this.entry, this.isDesktop = false});

  @override
  Widget build(BuildContext context) {
    final timeColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final payloadColor = _payloadColor(entry.type, context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
            '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
            '${entry.timestamp.second.toString().padLeft(2, '0')} ',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: timeColor,
            ),
          ),
          // Level indicator dot (mobile) or bracket tag (desktop)
          if (isDesktop)
            Text(
              '[${entry.type.toUpperCase().padRight(7)}] ',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: _levelDotColor(entry.type),
                fontWeight: FontWeight.bold,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _levelDotColor(entry.type),
                ),
                child: const SizedBox(width: 8, height: 8),
              ),
            ),
          // Payload
          Expanded(
            child: SelectableText(
              entry.payload,
              style: TextStyle(
                fontSize: isDesktop ? 12 : 12,
                fontFamily: 'monospace',
                height: 1.5,
                color: payloadColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _payloadColor(String type, BuildContext context) {
    switch (type) {
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      default:
        return Theme.of(context).colorScheme.onSurface;
    }
  }

  Color _levelDotColor(String type) {
    switch (type) {
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'debug':
        return Colors.grey;
      default:
        return Colors.green;
    }
  }
}
