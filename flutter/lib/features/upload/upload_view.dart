// lib/features/upload/upload_view.dart
//
// HomePage：当前项目 + 选照片 + 上传进度 + FAB 设置入口。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/mock/seed_data.dart';
import '../../ui/components/buttons.dart';
import '../../ui/components/cards.dart';
import '../../ui/components/starfield_bg.dart';
import '../../ui/tokens/colors.dart';
import '../../ui/tokens/radii.dart';
import '../../ui/tokens/spacing.dart';
import '../../ui/tokens/typography.dart';
import '../connection/connection_service.dart';
import '../project/project_service.dart';
import 'upload_service.dart';

class UploadView extends StatefulWidget {
  const UploadView({
    super.key,
    required this.connection,
    required this.projects,
    required this.uploader,
  });

  final ConnectionService connection;
  final ProjectService projects;
  final UploadService uploader;

  @override
  State<UploadView> createState() => _UploadViewState();
}

class _UploadViewState extends State<UploadView> {
  List<SelectedFile> _selected = [];
  bool _uploading = false;
  double _progress = 0; // 0..1
  bool _hasPicked = false;

  Project? get _currentProject {
    final list = widget.projects;
    if (list.currentProjectName == null) return null;
    return mockProjects.firstWhere(
      (p) => p.name == list.currentProjectName,
      orElse: () => mockProjects.firstWhere((p) => p.isCurrent),
    );
  }

  void _pickFiles() {
    setState(() {
      _selected = List.of(mockFiles);
      _hasPicked = true;
    });
  }

  Future<void> _upload() async {
    if (_selected.isEmpty) return;
    final projectName = _currentProject?.name ?? mockProjects.first.name;
    setState(() {
      _uploading = true;
      _progress = 0;
    });
    try {
      await widget.uploader.upload(
        projectName: projectName,
        files: _selected,
        onProgress: (cur, total) {
          if (!mounted) return;
          setState(() => _progress = cur / total);
        },
      );
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _progress = 0;
        _selected = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已上传 ${_selected.length} 张')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _progress = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('上传失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pc = widget.connection is ConnectionMock
        ? (widget.connection as ConnectionMock).connected
        : null;
    final pcName = pc?.name ?? 'PC';
    final current = _currentProject;

    return Scaffold(
      backgroundColor: AppColors.space900,
      appBar: AppBar(title: Text('⭐  $pcName')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/settings'),
        backgroundColor: AppColors.space700,
        foregroundColor: AppColors.star100,
        elevation: 0,
        child: const Icon(Icons.settings_outlined),
      ),
      body: StarfieldBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前项目',
                    style: AppTextStyle.bodyMd
                        .copyWith(color: AppColors.star300)),
                const SizedBox(height: AppSpace.sm),
                ProjectCard(
                  name: current?.name ?? '(未打开项目)',
                  fileCount: current?.fileCount ?? 0,
                  sizeLabel: current?.sizeLabel ?? '-',
                  isCurrent: current != null,
                  trailing: TextButton(
                    onPressed: () => context.push('/home/project-switcher'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.nebula400,
                    ),
                    child: const Text('切换'),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                if (!_hasPicked)
                  PrimaryButton(
                    label: '+ 选择照片',
                    onPressed: _pickFiles,
                  )
                else ...[
                  Text('已选 ${_selected.length} 张',
                      style: AppTextStyle.bodyMd
                          .copyWith(color: AppColors.star300)),
                  const SizedBox(height: AppSpace.sm),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.space800,
                        borderRadius: AppRadius.borderMd,
                        border: Border.all(color: AppColors.border12),
                      ),
                      child: ListView.separated(
                        itemCount: _selected.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: AppColors.border12,
                        ),
                        itemBuilder: (_, i) {
                          final f = _selected[i];
                          return ListTile(
                            leading: const Icon(Icons.photo_outlined,
                                color: AppColors.nebula400),
                            title: Text(f.name,
                                style: AppTextStyle.bodyLg
                                    .copyWith(color: AppColors.star100)),
                            subtitle: Text(f.sizeLabel,
                                style: AppTextStyle.caption
                                    .copyWith(color: AppColors.star300)),
                            trailing: IconButton(
                              icon: const Icon(Icons.close,
                                  color: AppColors.star300),
                              onPressed: _uploading
                                  ? null
                                  : () => setState(() {
                                        _selected.removeAt(i);
                                        if (_selected.isEmpty) {
                                          _hasPicked = false;
                                        }
                                      }),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  PrimaryButton(
                    label: _uploading
                        ? '上传中 ${(_progress * 100).toInt()}%'
                        : '上传 ${_selected.length} 张',
                    loading: _uploading,
                    loadingLabel: '上传中 ${(_progress * 100).toInt()}%',
                    onPressed: _uploading ? null : _upload,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}