// lib/features/project/project_switcher.dart

import 'package:flutter/material.dart';

import '../../core/mock/seed_data.dart';
import '../../ui/components/cards.dart';
import '../../ui/components/empty_state.dart';
import '../../ui/tokens/colors.dart';
import '../../ui/tokens/spacing.dart';
import '../../ui/tokens/typography.dart';
import 'project_service.dart';

class ProjectSwitcher extends StatefulWidget {
  const ProjectSwitcher({super.key, required this.projects});

  final ProjectService projects;

  @override
  State<ProjectSwitcher> createState() => _ProjectSwitcherState();
}

class _ProjectSwitcherState extends State<ProjectSwitcher> {
  late Future<List<Project>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.projects.listProjects();
  }

  Future<void> _onSelect(Project p) async {
    await widget.projects.switchTo(p.name);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.space800,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: AppSpace.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.space600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            const Text('选择项目', style: AppTextStyle.titleLg),
            const SizedBox(height: AppSpace.md),
            Expanded(
              child: FutureBuilder<List<Project>>(
                future: _future,
                builder: (_, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.nebula400),
                    );
                  }
                  final items = snap.data ?? [];
                  if (items.isEmpty) {
                    return const EmptyState(
                      icon: Icons.folder_off_outlined,
                      title: '还没有任何项目',
                      description: '请到 PC 端添加项目',
                    );
                  }
                  return ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                      vertical: AppSpace.sm,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpace.sm),
                    itemBuilder: (_, i) {
                      final p = items[i];
                      return ProjectCard(
                        name: p.name,
                        fileCount: p.fileCount,
                        sizeLabel: p.sizeLabel,
                        isCurrent: p.isCurrent,
                        onTap: () => _onSelect(p),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}