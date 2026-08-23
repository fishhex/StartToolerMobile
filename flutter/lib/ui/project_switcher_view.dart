// lib/ui/project_switcher_view.dart
//
// /home/project-switcher：空间列表 + 切换 + 删除 + 添加。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/spaces_controller.dart';

class ProjectSwitcherView extends StatelessWidget {
  const ProjectSwitcherView({super.key});

  @override
  Widget build(BuildContext context) {
    final spaces = context.watch<SpacesController>();
    return Scaffold(
      appBar: AppBar(title: const Text('切换空间')),
      body: ListView(
        children: [
          for (final s in spaces.spaces)
            ListTile(
              leading: Icon(
                s.name == spaces.activeName ? Icons.check_circle : Icons.circle_outlined,
                color: s.name == spaces.activeName ? Colors.green : null,
              ),
              title: Text(s.name),
              subtitle: Text('${s.ip}:${s.port}'),
              trailing: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: s.name == spaces.activeName
                        ? null
                        : () async {
                            await spaces.setActive(s.name);
                            if (context.mounted) context.go('/home');
                          },
                    child: const Text('切换'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await _confirmDelete(context, s.name);
                      if (ok == true) {
                        await spaces.remove(s.name);
                      }
                    },
                  ),
                ],
              ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('+ 添加空间'),
            onTap: () => context.go('/connect'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('删除 $name？'),
        content: const Text('该空间将从本机移除，下次连接需要重新扫码。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(_, true), child: const Text('删除')),
        ],
      ),
    );
  }
}