// lib/ui/home_view.dart
//
// /home：顶栏 PC 名 + 当前项目 Card + 其他项目 ListView + 切换/上传按钮。
//
// T3：「上传」按钮 → 系统 Photo Picker → 串行 multipart → 进度条 → SnackBar。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/health_api.dart';
import '../core/projects_api.dart';
import '../core/spaces_controller.dart';
import '../core/upload_api.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  String? _pcName;
  List<Project> _projects = const [];
  bool _loading = false;
  String? _errorText;

  // 上传状态
  bool _uploading = false;
  int _sent = 0;
  int _totalUpload = 0;

  final _uploadApi = UploadApi();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  Future<void> _loadAll() async {
    final spaces = context.read<SpacesController>();
    final active = spaces.active;
    if (active == null) {
      if (mounted) context.go('/connect');
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
    });

    final healthApi = context.read<HealthApi>();
    final projectsApi = context.read<ProjectsApi>();
    final health = await healthApi.check(active.ip, active.port);
    final projects = await projectsApi.list(active.ip, active.port, active.secret);

    if (!mounted) return;
    setState(() {
      _loading = false;
    });

    health.when(
      ok: (h) => _pcName = h.name,
      err: (_) => _pcName = active.name,
    );
    projects.when(
      ok: (list) => _projects = list,
      err: (e) => _errorText = e.toString(),
    );
  }

  Future<void> _pickAndUpload() async {
    final active = context.read<SpacesController>().active;
    if (active == null) return;
    final current = _projects.where((p) => p.isCurrent).firstOrNull;
    if (current == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有「当前项目」，请在 PC 端激活一个项目')),
      );
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isEmpty) return;

    final files = <UploadFile>[];
    for (final x in picked) {
      final len = await x.length();
      files.add(UploadFile(path: x.path, bytes: len));
    }

    setState(() {
      _uploading = true;
      _sent = 0;
      _totalUpload = files.length;
    });

    final outcome = await _uploadApi.upload(
      host: active.ip,
      port: active.port,
      projectName: current.name,
      secret: active.secret,
      files: files,
      progressCb: (p) {
        if (!mounted) return;
        setState(() => _sent = p.sent);
      },
    );

    if (!mounted) return;
    setState(() => _uploading = false);

    final reasonText = (UploadFailureKind k) {
      switch (k) {
        case UploadFailureKind.tooLarge:
          return '文件超过 500MB';
        case UploadFailureKind.unsupportedType:
          return '扩展名不在白名单';
        case UploadFailureKind.unauthorized:
          return 'PC 端密钥已重置';
        case UploadFailureKind.network:
          return '网络断开';
        case UploadFailureKind.timeout:
          return '上传超时';
        case UploadFailureKind.serverError:
          return 'PC 端返回错误';
        case UploadFailureKind.badResponse:
          return '响应解析失败';
      }
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome.failed.isEmpty
              ? '上传完成：成功 ${outcome.uploaded.length}'
              : '上传完成：成功 ${outcome.uploaded.length}，失败 ${outcome.failed.length}\n'
                  + outcome.failed
                      .take(3)
                      .map((f) => '· ${f.name.split('/').last}：${reasonText(f.kind)}')
                      .join('\n'),
        ),
        duration: const Duration(seconds: 4),
      ),
    );

    // 成功后刷新项目文件数
    if (outcome.uploaded.isNotEmpty) {
      await _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = context.watch<SpacesController>().active;
    return Scaffold(
      appBar: AppBar(
        title: Text(_pcName ?? active?.name ?? '加载中…'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: '切换空间',
            onPressed: () => context.go('/home/project-switcher'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_uploading) LinearProgressIndicator(
            value: _totalUpload == 0 ? null : _sent / _totalUpload,
            minHeight: 6,
          ),
          if (_uploading) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('已传 $_sent / $_totalUpload'),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAll,
              child: _buildBody(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _pickAndUpload,
        icon: const Icon(Icons.upload),
        label: const Text('上传'),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _projects.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorText != null && _projects.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(child: Text('加载失败：$_errorText')),
        ],
      );
    }
    if (_projects.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(child: Text('暂无项目')),
        ],
      );
    }

    final current = _projects.where((p) => p.isCurrent).toList();
    final others = _projects.where((p) => !p.isCurrent).toList();

    return ListView(
      children: [
        if (current.isNotEmpty) ...[
          Card(
            child: ListTile(
              title: Text(current.first.name),
              subtitle: Text('${current.first.fileCount} 个文件 · '
                  '${(current.first.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'),
              trailing: const Chip(label: Text('当前')),
            ),
          ),
        ],
        if (others.isNotEmpty) ...const [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('其他项目', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
        ...others.map((p) => ListTile(
              title: Text(p.name),
              subtitle: Text('${p.fileCount} 个文件'),
            )),
      ],
    );
  }
}

extension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}