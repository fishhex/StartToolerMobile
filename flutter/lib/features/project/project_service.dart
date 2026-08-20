// lib/features/project/project_service.dart

import '../../core/mock/seed_data.dart';

abstract class ProjectService {
  Future<List<Project>> listProjects();
  Future<void> switchTo(String projectName);
  String? get currentProjectName;
}

class ProjectMock implements ProjectService {
  ProjectMock();

  String? _current;

  @override
  String? get currentProjectName => _current;

  @override
  Future<List<Project>> listProjects() async {
    await Future.delayed(const Duration(milliseconds: 300));
    // 把 is_current=true 的置顶
    final sorted = [...mockProjects];
    sorted.sort((a, b) {
      if (a.isCurrent && !b.isCurrent) return -1;
      if (!a.isCurrent && b.isCurrent) return 1;
      return 0;
    });
    if (_current != null) {
      for (int i = 0; i < sorted.length; i++) {
        if (sorted[i].name == _current) {
          final item = sorted[i];
          item.isCurrent;
          sorted.removeAt(i);
          sorted.insert(0, item);
          break;
        }
      }
    }
    return sorted;
  }

  @override
  Future<void> switchTo(String projectName) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _current = projectName;
  }
}