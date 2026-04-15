import 'package:flutter/material.dart';

import '../../../theme.dart';

class DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const DetailRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label, style: YLText.body.copyWith(color: YLColors.zinc500)),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: YLText.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
