// test/widget_test.dart
//
// 冒烟测试：验证 StartToolerApp 可启动并渲染首屏。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:starttooler_mobile/app/app.dart';
import 'package:starttooler_mobile/core/mock/seed_data.dart';
import 'package:starttooler_mobile/core/token_store_in_memory.dart';
import 'package:starttooler_mobile/features/connection/connection_service.dart';
import 'package:starttooler_mobile/features/discovery/discovery_service.dart';
import 'package:starttooler_mobile/features/project/project_service.dart';
import 'package:starttooler_mobile/features/upload/upload_service.dart';

void main() {
  testWidgets('App builds and shows a Scaffold', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        StartToolerApp(
          discovery: DiscoveryMock(),
          connection: HttpConnectionService(tokenStore: InMemoryTokenStore()),
          projects: ProjectMock(),
          uploader: UploadMock(),
        ),
      );
      // 首帧已渲染：Scaffold 一定存在。
      expect(find.byType(Scaffold), findsWidgets);
      // runAsync 让 FakeAsync 之外的 Timer 跑起来再释放，避免 pending 校验失败。
      await Future<void>.delayed(const Duration(seconds: 6));
    });
  });

  test('Seed data: mockPCs has 2 entries and 1 is current', () {
    expect(mockPCs.length, 2);
    expect(mockPCs.first.currentProject, 'deepsky-2025');
    expect(mockPCs.last.currentProject, isNull);
    expect(mockProjects.length, 3);
    expect(mockProjects.first.isCurrent, true);
    expect(mockFiles.length, 5);
    expect(mockValidToken, '123456');
  });
}