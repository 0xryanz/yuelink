import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Platform-native loading indicator: Cupertino spinner on iOS/macOS,
/// Material progress on Android/Windows/Linux.
class YLLoading extends StatelessWidget {
  final double? size;
  final Color? color;

  const YLLoading({super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS || Platform.isMacOS) {
      return CupertinoActivityIndicator(
        radius: (size ?? 20) / 2,
        color: color,
      );
    }
    return SizedBox(
      width: size ?? 24,
      height: size ?? 24,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: color,
      ),
    );
  }
}
