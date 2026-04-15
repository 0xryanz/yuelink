import 'package:flutter/material.dart';

import '../../../domain/models/rule.dart';

class RuleTile extends StatelessWidget {
  final RuleInfo rule;
  const RuleTile({super.key, required this.rule});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 96,
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _typeColor(context).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              rule.type,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _typeColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.payload.isEmpty ? '*' : rule.payload,
                  style: const TextStyle(
                      fontSize: 12, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
                if (rule.size > 0)
                  Text('${rule.size} 条',
                      style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              rule.proxy,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context)
                    .colorScheme
                    .onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(BuildContext context) {
    switch (rule.type) {
      case 'DOMAIN-SUFFIX':
      case 'DOMAIN':
        return Colors.blue;
      case 'DOMAIN-KEYWORD':
        return Colors.teal;
      case 'GEOIP':
        return Colors.orange;
      case 'RULE-SET':
        return Colors.purple;
      case 'MATCH':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}
