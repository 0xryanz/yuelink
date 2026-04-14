import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/widgets/empty_state.dart';

void main() {
  testWidgets('YLEmptyState renders icon and title', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: YLEmptyState(
          icon: Icons.inbox_outlined,
          title: 'No data',
        ),
      ),
    ));
    expect(find.text('No data'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });

  testWidgets('YLEmptyState shows subtitle and action when provided',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: YLEmptyState(
          icon: Icons.inbox_outlined,
          title: 'No data',
          subtitle: 'Try again later',
          action: TextButton(onPressed: () {}, child: const Text('Retry')),
        ),
      ),
    ));
    expect(find.text('Try again later'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
