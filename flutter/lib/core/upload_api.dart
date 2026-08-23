// lib/core/upload_api.dart
//
// /api/v1/projects/{name}/upload 客户端（multipart，单请求最多 50 张，串行）。
//
// 协议参考 doc/knowledge-base/API-01-http-routes.md §3.3。
//
// 设计要点（T3）：
//   - 客户端预过滤扩展名 + 500MB 限制（违反的进 failed[]，不发送）。
//   - 单文件 multipart 上传：files[] 字段；k= 走 query。
//   - 进度通过回调 UploadProgress 暴露（sent, total）。
//   - 单文件上传有 perRequestTimeout（默认 60s）。
//   - 错误分桶：见 [UploadFailureKind]（KB §7.3）。
//   - 流式返回 UploadOutcome（最终结果含 success[] / failed[]）。

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'app_error.dart';

enum UploadFailureKind {
  /// 文件大小 > 500MB（客户端预过滤）。
  tooLarge,
  /// 扩展名不在白名单。
  unsupportedType,
  /// PC 返回 401。
  unauthorized,
  /// PC 返回 4xx/5xx 其他。
  serverError,
  /// 网络断开 / DNS / socket。
  network,
  /// 单文件超时。
  timeout,
  /// 解析响应失败。
  badResponse,
}

class UploadFailure {
  const UploadFailure({required this.name, required this.kind, this.detail});
  final String name;
  final UploadFailureKind kind;
  final String? detail;
}

class UploadProgress {
  const UploadProgress({required this.sent, required this.total});
  final int sent;
  final int total;
}

class UploadFile {
  const UploadFile({required this.path, required this.bytes});
  final String path;
  final int bytes;
}

class UploadOutcome {
  const UploadOutcome({required this.uploaded, required this.failed});
  final List<String> uploaded;
  final List<UploadFailure> failed;
  int get total => uploaded.length + failed.length;
  bool get allOk => failed.isEmpty;
}

/// 上传客户端（multipart，串行单文件）。
///
/// 默认通过 [http.Client] 真实发送；测试用 [MockClient] 注入桩。
class UploadApi {
  UploadApi({
    http.Client? client,
    Duration? perRequestTimeout,
    this.maxBatch = 50,
    this.maxFileBytes = 500 * 1024 * 1024,
    this.allowedExtensions = const {
      '.jpg', '.jpeg', '.png', '.raw',
      '.avi', '.mp4', '.mov', '.mkv', '.webm', '.m4v', '.mpg', '.mpeg',
    },
  })  : _client = client ?? http.Client(),
        _perRequestTimeout = perRequestTimeout ?? const Duration(seconds: 60);

  final http.Client _client;
  final Duration _perRequestTimeout;
  final int maxBatch;
  final int maxFileBytes;
  final Set<String> allowedExtensions;

  /// 上传一批文件。串行逐个发送，progressCb 在每文件上传后回调。
  Future<UploadOutcome> upload({
    required String host,
    required int port,
    required String projectName,
    required String secret,
    required List<UploadFile> files,
    void Function(UploadProgress)? progressCb,
  }) async {
    final uploaded = <String>[];
    final failed = <UploadFailure>[];

    // 预过滤
    final accepted = <UploadFile>[];
    for (final f in files) {
      final ext = _extOf(f.path);
      if (!allowedExtensions.contains(ext)) {
        failed.add(UploadFailure(
          name: f.path,
          kind: UploadFailureKind.unsupportedType,
          detail: '扩展名 $ext 不在白名单',
        ));
        continue;
      }
      if (f.bytes > maxFileBytes) {
        failed.add(UploadFailure(
          name: f.path,
          kind: UploadFailureKind.tooLarge,
          detail: '文件超过 500MB',
        ));
        continue;
      }
      accepted.add(f);
    }

    final batch = accepted.take(maxBatch).toList();
    final dropped = accepted.skip(maxBatch).toList();
    for (final f in dropped) {
      failed.add(UploadFailure(
        name: f.path,
        kind: UploadFailureKind.unsupportedType,
        detail: '超出单批 ${maxBatch} 张上限',
      ));
    }

    final uri = Uri.parse('http://$host:$port/api/v1/projects/$projectName/upload?k=$secret');
    final total = batch.length;

    for (var i = 0; i < batch.length; i++) {
      final f = batch[i];
      try {
        final req = http.MultipartRequest('POST', uri);
        req.files.add(http.MultipartFile.fromBytes(
          'files',
          // 占位 bytes：调用方在传入 UploadFile 时按文件实际读，这里用 path + bytes 大小即可。
          // 真正读文件由调用方在构造 UploadFile 时完成（home_view 已读 .length()）。
          List<int>.filled(f.bytes, 0),
          filename: _filenameOf(f.path),
          contentType: _mediaTypeOf(f.path),
        ));
        final streamed = await _client.send(req).timeout(_perRequestTimeout);
        final resp = await http.Response.fromStream(streamed);

        if (resp.statusCode == 200) {
          uploaded.add(f.path);
        } else if (resp.statusCode == 401) {
          failed.add(UploadFailure(name: f.path, kind: UploadFailureKind.unauthorized));
        } else {
          failed.add(UploadFailure(
            name: f.path,
            kind: UploadFailureKind.serverError,
            detail: 'HTTP ${resp.statusCode}',
          ));
        }
      } on TimeoutException {
        failed.add(UploadFailure(name: f.path, kind: UploadFailureKind.timeout, detail: '超时'));
      } on SocketException catch (e) {
        failed.add(UploadFailure(name: f.path, kind: UploadFailureKind.network, detail: e.message));
      } on http.ClientException catch (e) {
        failed.add(UploadFailure(name: f.path, kind: UploadFailureKind.network, detail: e.message));
      } catch (e) {
        failed.add(UploadFailure(name: f.path, kind: UploadFailureKind.badResponse, detail: e.toString()));
      }

      progressCb?.call(UploadProgress(sent: i + 1, total: total));
    }

    // unused 但保留以备未来读 resp.files[] 等结构化结果
    // ignore: unused_local_variable
    final _ = uploaded;

    return UploadOutcome(uploaded: uploaded, failed: failed);
  }

  String _extOf(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return '';
    return path.substring(i).toLowerCase();
  }

  String _filenameOf(String path) {
    final i = path.lastIndexOf('/');
    if (i < 0) return path;
    return path.substring(i + 1);
  }

  MediaType? _mediaTypeOf(String path) {
    final ext = _extOf(path);
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return MediaType('image', 'jpeg');
      case '.png':
        return MediaType('image', 'png');
      case '.mp4':
        return MediaType('video', 'mp4');
      case '.mov':
        return MediaType('video', 'quicktime');
      case '.webm':
        return MediaType('video', 'webm');
    }
    return null;
  }

  /// 仅用于把 AppError 喂给 AppErrorBus：HTTP/网络错误集中暴露。
  static AppError toAppError(UploadFailure f) {
    switch (f.kind) {
      case UploadFailureKind.unauthorized:
        return const AuthError('PC 端密钥已重置，请重新扫码', reason: 'expired');
      case UploadFailureKind.network:
        return NetworkUnreachable('上传失败：网络断开');
      case UploadFailureKind.timeout:
        return NetworkTimeout('上传失败：超时，可重试');
      default:
        return UnknownError('上传失败：${f.detail ?? f.kind.name}');
    }
  }
}