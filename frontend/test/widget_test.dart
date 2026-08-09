import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peak_coach_ai/main.dart';

void main() {
  testWidgets('App boots without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: PeakCoachApp()));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
