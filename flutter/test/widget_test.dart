// test/widget_test.dart
//
// T1 + T2 单测：QR 解析、health 客户端、projects 客户端、SecureStore、SpacesController。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starttooler_mobile/core/app_error.dart';
import 'package:starttooler_mobile/core/health_api.dart';
import 'package:starttooler_mobile/core/projects_api.dart';
import 'package:starttooler_mobile/core/qr_parser.dart';
import 'package:starttooler_mobile/core/result.dart';
import 'package:starttooler_mobile/core/secure_store.dart';
import 'package:starttooler_mobile/core/space.dart';
import 'package:starttooler_mobile/core/spaces_controller.dart';
import 'package:starttooler_mobile/core/strings.dart';
import 'package:starttooler_mobile/core/upload_api.dart';

void main() {
  group('parseQr', () {
    test('合法 http + IPv4 + port + secret', () {
      final p = parseQr('http://192.168.1.10:9527/upload?k=0123456789abcdef0123456789abcdef');
      expect(p.host, '192.168.1.10');
      expect(p.port, 9527);
      expect(p.secret, '0123456789abcdef0123456789abcdef');
    });

    test('合法 IPv6', () {
      final p = parseQr('http://[fe80::1]:9527/upload?k=0123456789abcdef0123456789abcdef');
      expect(p.host.startsWith('fe80'), true);
      expect(p.port, 9527);
    });

    test('port 越界', () {
      expect(
        () => parseQr('http://1.1.1.1:99999/upload?k=0123456789abcdef0123456789abcdef'),
        throwsA(isA<QrInvalidPort>()),
      );
    });

    test('secret 长度错', () {
      expect(
        () => parseQr('http://1.1.1.1:9527/upload?k=deadbeef'),
        throwsA(isA<QrMissingSecret>()),
      );
    });

    test('非 http 协议', () {
      expect(
        () => parseQr('https://1.1.1.1:9527/upload?k=0123456789abcdef0123456789abcdef'),
        throwsA(isA<QrInvalidFormat>()),
      );
    });

    test('缺 ?k=', () {
      expect(
        () => parseQr('http://1.1.1.1:9527/upload'),
        throwsA(isA<QrMissingSecret>()),
      );
    });

    test('多个 ?k= 取首个', () {
      final p = parseQr(
          'http://1.1.1.1:9527/upload?k=0123456789abcdef0123456789abcdef&k=ffffffffffffffffffffffffffffffff');
      expect(p.secret, '0123456789abcdef0123456789abcdef');
    });

    test('空字符串', () {
      expect(() => parseQr(''), throwsA(isA<QrInvalidFormat>()));
    });

    test('非法 host', () {
      expect(
        () => parseQr('http://not_an_ip:9527/upload?k=0123456789abcdef0123456789abcdef'),
        throwsA(isA<QrInvalidHost>()),
      );
    });

    test('path 不是 /upload', () {
      expect(
        () => parseQr('http://1.1.1.1:9527/foo?k=0123456789abcdef0123456789abcdef'),
        throwsA(isA<QrInvalidFormat>()),
      );
    });
  });

  group('HealthApi', () {
    test('200 → Ok(Health)', () async {
      final mock = MockClient((req) async {
        expect(req.url.path, '/api/v1/health');
        return http.Response(
          jsonEncode({
            'name': 'DevPC',
            'version': '0.14.0',
            'port': 9527,
            'secret': 'aabbccddaabbccddaabbccddaabbccdd',
            'currentProject': 'main',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = HealthApi(client: mock);
      final r = await api.check('127.0.0.1', 9527);
      expect(r, isA<Ok<Health, AppError>>());
      r.when(
        ok: (h) {
          expect(h.name, 'DevPC');
          expect(h.currentProject, 'main');
        },
        err: (_) => fail('expected Ok'),
      );
    });

    test('404 → HttpError(404)', () async {
      final mock = MockClient((_) async => http.Response('not found', 404));
      final api = HealthApi(client: mock);
      final r = await api.check('127.0.0.1', 9527);
      expect(r, isA<Err<Health, AppError>>());
      r.when(
        ok: (_) => fail('expected Err'),
        err: (e) {
          expect(e, isA<HttpError>());
          expect((e as HttpError).status, 404);
        },
      );
    });

    test('500 → HttpError(500)', () async {
      final mock = MockClient((_) async => http.Response('boom', 500));
      final api = HealthApi(client: mock);
      final r = await api.check('127.0.0.1', 9527);
      r.when(
        ok: (_) => fail('expected Err'),
        err: (e) => expect((e as HttpError).status, 500),
      );
    });

    test('timeout → NetworkTimeout', () async {
      final mock = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return http.Response('{}', 200);
      });
      final api = HealthApi(client: mock, defaultTimeout: const Duration(milliseconds: 50));
      final r = await api.check('127.0.0.1', 9527);
      r.when(
        ok: (_) => fail('expected Err'),
        err: (e) => expect(e, isA<NetworkTimeout>()),
      );
    });
  });

  group('ProjectsApi', () {
    test('200 → Ok(list)', () async {
      final mock = MockClient((req) async {
        expect(req.url.path, '/api/v1/projects');
        expect(req.url.queryParameters['k'], '0123456789abcdef0123456789abcdef');
        return http.Response(
          jsonEncode({
            'projects': [
              {'name': 'main', 'isCurrent': true, 'fileCount': 12, 'sizeBytes': 1024},
              {'name': 'travel', 'isCurrent': false, 'fileCount': 3, 'sizeBytes': 256},
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = ProjectsApi(client: mock);
      final r = await api.list('127.0.0.1', 9527, '0123456789abcdef0123456789abcdef');
      expect(r, isA<Ok<List<Project>, AppError>>());
      r.when(
        ok: (list) {
          expect(list.length, 2);
          expect(list.first.name, 'main');
          expect(list.first.isCurrent, true);
        },
        err: (_) => fail('expected Ok'),
      );
    });

    test('401 → AuthError', () async {
      final mock = MockClient((_) async => http.Response('expired', 401));
      final api = ProjectsApi(client: mock);
      final r = await api.list('127.0.0.1', 9527, '0' * 32);
      r.when(
        ok: (_) => fail('expected Err'),
        err: (e) => expect(e, isA<AuthError>()),
      );
    });

    test('500 → HttpError', () async {
      final mock = MockClient((_) async => http.Response('boom', 500));
      final api = ProjectsApi(client: mock);
      final r = await api.list('127.0.0.1', 9527, '0' * 32);
      r.when(
        ok: (_) => fail('expected Err'),
        err: (e) => expect((e as HttpError).status, 500),
      );
    });

    test('timeout → NetworkTimeout', () async {
      final mock = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return http.Response('{}', 200);
      });
      final api = ProjectsApi(client: mock, defaultTimeout: const Duration(milliseconds: 50));
      final r = await api.list('127.0.0.1', 9527, '0' * 32);
      r.when(
        ok: (_) => fail('expected Err'),
        err: (e) => expect(e, isA<NetworkTimeout>()),
      );
    });
  });

  group('SecureStore（_FakeSecureStore 内存版）', () {
    test('读空', () async {
      final store = _FakeSecureStore();
      expect(await store.readAll(), isEmpty);
      expect(await store.activeName(), null);
      expect(await store.readCurrent(), null);
    });

    test('upsertAndActivate + readCurrent + activeName', () async {
      final store = _FakeSecureStore();
      final s1 = Space(name: 'A', ip: '1.1.1.1', port: 9527, secret: 'a' * 32, lastSeenAt: DateTime.now());
      await store.upsertAndActivate(s1);
      expect((await store.readCurrent())?.name, 'A');
      expect(await store.activeName(), 'A');
      expect((await store.readAll()).length, 1);
    });

    test('remove 会清 active', () async {
      final store = _FakeSecureStore();
      final s1 = Space(name: 'A', ip: '1.1.1.1', port: 9527, secret: 'a' * 32, lastSeenAt: DateTime.now());
      await store.upsertAndActivate(s1);
      await store.remove('A');
      expect(await store.activeName(), null);
      expect(await store.readCurrent(), null);
      expect(await store.readAll(), isEmpty);
    });
  });

  group('SpacesController', () {
    test('upsert → list 出现 + activeName 更新', () async {
      final store = _FakeSecureStore();
      final ctl = SpacesController(store);
      await ctl.load();
      expect(ctl.spaces, isEmpty);

      final s = Space(name: 'A', ip: '1.1.1.1', port: 9527, secret: 'a' * 32, lastSeenAt: DateTime.now());
      await ctl.upsertAndActivate(s);

      expect(ctl.spaces.length, 1);
      expect(ctl.activeName, 'A');
      expect(ctl.active?.name, 'A');
    });

    test('remove 后 list 为空 + activeName 清空', () async {
      final store = _FakeSecureStore();
      final ctl = SpacesController(store);
      final s = Space(name: 'A', ip: '1.1.1.1', port: 9527, secret: 'a' * 32, lastSeenAt: DateTime.now());
      await ctl.upsertAndActivate(s);
      await ctl.remove('A');
      expect(ctl.spaces, isEmpty);
      expect(ctl.activeName, null);
    });
  });

  group('UploadApi', () {
    test('200/全部成功', () async {
      final mock = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/api/v1/projects/main/upload');
        expect(req.url.queryParameters['k'], '0' * 32);
        return http.Response('{"success":true}', 200);
      });
      final api = UploadApi(client: mock);
      final out = await api.upload(
        host: '127.0.0.1',
        port: 9527,
        projectName: 'main',
        secret: '0' * 32,
        files: [
          UploadFile(path: '/tmp/a.jpg', bytes: 100),
          UploadFile(path: '/tmp/b.png', bytes: 200),
        ],
      );
      expect(out.uploaded.length, 2);
      expect(out.failed, isEmpty);
    });

    test('200/部分失败：服务端返回 200 + 自定义结构', () async {
      // 我们当前的实现是 200 → 成功；非 200 → 失败桶。
      // 这里 mock 部分 200 部分 500，验证桶。
      var i = 0;
      final mock = MockClient((req) async {
        final ok = i++ == 0;
        return http.Response(ok ? '{}' : 'boom', ok ? 200 : 500);
      });
      final api = UploadApi(client: mock);
      final out = await api.upload(
        host: '127.0.0.1',
        port: 9527,
        projectName: 'main',
        secret: '0' * 32,
        files: [
          UploadFile(path: '/tmp/a.jpg', bytes: 100),
          UploadFile(path: '/tmp/b.jpg', bytes: 100),
        ],
      );
      expect(out.uploaded.length, 1);
      expect(out.failed.length, 1);
      expect(out.failed.first.kind, UploadFailureKind.serverError);
    });

    test('401 → unauthorized 桶', () async {
      final mock = MockClient((_) async => http.Response('expired', 401));
      final api = UploadApi(client: mock);
      final out = await api.upload(
        host: '127.0.0.1',
        port: 9527,
        projectName: 'main',
        secret: '0' * 32,
        files: [UploadFile(path: '/tmp/a.jpg', bytes: 100)],
      );
      expect(out.failed.first.kind, UploadFailureKind.unauthorized);
    });

    test('扩展名不在白名单：直接进 failed，不发请求', () async {
      var requests = 0;
      final mock = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      final api = UploadApi(client: mock);
      final out = await api.upload(
        host: '127.0.0.1',
        port: 9527,
        projectName: 'main',
        secret: '0' * 32,
        files: [
          UploadFile(path: '/tmp/a.txt', bytes: 100),
          UploadFile(path: '/tmp/b.exe', bytes: 100),
        ],
      );
      expect(out.uploaded, isEmpty);
      expect(out.failed.length, 2);
      expect(requests, 0);
    });

    test('500MB 过滤', () async {
      final mock = MockClient((_) async => http.Response('{}', 200));
      final api = UploadApi(client: mock, maxFileBytes: 1024);
      final out = await api.upload(
        host: '127.0.0.1',
        port: 9527,
        projectName: 'main',
        secret: '0' * 32,
        files: [UploadFile(path: '/tmp/big.jpg', bytes: 2048)],
      );
      expect(out.failed.length, 1);
      expect(out.failed.first.kind, UploadFailureKind.tooLarge);
    });

    test('>50 张截断', () async {
      final mock = MockClient((_) async => http.Response('{}', 200));
      final api = UploadApi(client: mock, maxBatch: 3);
      final files = List.generate(5, (i) => UploadFile(path: '/tmp/$i.jpg', bytes: 10));
      final out = await api.upload(
        host: '127.0.0.1',
        port: 9527,
        projectName: 'main',
        secret: '0' * 32,
        files: files,
      );
      expect(out.uploaded.length, 3);
      expect(out.failed.length, 2);
      expect(out.failed.first.kind, UploadFailureKind.unsupportedType);
    });

    test('单文件超时', () async {
      final mock = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return http.Response('{}', 200);
      });
      final api = UploadApi(client: mock, perRequestTimeout: const Duration(milliseconds: 50));
      final out = await api.upload(
        host: '127.0.0.1',
        port: 9527,
        projectName: 'main',
        secret: '0' * 32,
        files: [UploadFile(path: '/tmp/a.jpg', bytes: 10)],
      );
      expect(out.failed.first.kind, UploadFailureKind.timeout);
    });
  });

  group('Strings.formatError', () {
    test('AuthError → 重置 secret', () {
      expect(Strings.formatError(const AuthError('x')), Strings.errorUnauthorized);
    });

    test('NetworkUnreachable → 连不上', () {
      expect(
        Strings.formatError(const NetworkUnreachable('x')),
        Strings.errorNetworkUnreachable,
      );
    });

    test('NetworkTimeout → 超时', () {
      expect(Strings.formatError(const NetworkTimeout('x')), Strings.errorTimeout);
    });

    test('HttpError → 含 status', () {
      expect(Strings.formatError(const HttpError('x', status: 503)),
          contains('503'));
    });

    test('null → 空字符串', () {
      expect(Strings.formatError(null), '');
    });

    test('未知 Object → toString 透传', () {
      expect(Strings.formatError('custom error'), 'custom error');
    });
  });
}

/// SecureStore 的内存假实现 —— 用于单测。
class _FakeSecureStore implements SecureStore {
  final Map<String, String> _kv = {};

  static const _kAll = 'spaces.all.v1';
  static const _kCurrent = 'spaces.current.v1';
  static const _kActive = 'spaces.active.v1';

  @override
  Future<Space?> readCurrent() async => _kv[_kCurrent] == null
      ? null
      : Space.fromJson(jsonDecode(_kv[_kCurrent]!) as Map<String, dynamic>);

  @override
  Future<void> writeCurrent(Space s) async => _kv[_kCurrent] = jsonEncode(s.toJson());

  @override
  Future<List<Space>> readAll() async => _kv[_kAll] == null
      ? <Space>[]
      : (jsonDecode(_kv[_kAll]!) as List<dynamic>)
          .map((e) => Space.fromJson(e as Map<String, dynamic>))
          .toList();

  @override
  Future<void> writeAll(List<Space> spaces) async =>
      _kv[_kAll] = jsonEncode(spaces.map((e) => e.toJson()).toList());

  @override
  Future<void> remove(String name) async {
    final all = await readAll();
    await writeAll(all.where((s) => s.name != name).toList());
    if (_kv[_kActive] == name) {
      _kv.remove(_kActive);
      _kv.remove(_kCurrent);
    }
  }

  @override
  Future<String?> activeName() async => _kv[_kActive];

  @override
  Future<void> setActive(String name) async => _kv[_kActive] = name;

  @override
  Future<void> upsertAndActivate(Space s) async {
    final all = await readAll();
    final idx = all.indexWhere((x) => x.name == s.name);
    if (idx >= 0) {
      all[idx] = s;
    } else {
      all.add(s);
    }
    await writeAll(all);
    await writeCurrent(s);
    await setActive(s.name);
  }
}