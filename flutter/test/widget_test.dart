import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starttooler_mobile/main.dart';

void main() {
  testWidgets('renders hello! on home page', (WidgetTester tester) async {
    await tester.pumpWidget(const StartToolerApp());
    await tester.pumpAndSettle();
    expect(find.text('hello!'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
