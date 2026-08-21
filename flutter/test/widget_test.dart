// test/widget_test.dart
//
// 冒烟测试:验证 HelloApp 可启动并渲染首屏。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:starttooler_mobile/main.dart';

void main() {
  testWidgets('HelloApp shows greeting', (WidgetTester tester) async {
    await tester.pumpWidget(const HelloApp());
    expect(find.text('Hello, StartTooler!'), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
  });
}