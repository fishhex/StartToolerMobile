// lib/ui/settings_view.dart
//
// /settings：三个分组（PC / 缓存 / 关于）。

import 'package:flutter/material.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: const [
          ListTile(
            title: Text('PC', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(title: Text('当前 PC：—')),
          ListTile(title: Text('断开当前 PC')),
          Divider(),
          ListTile(
            title: Text('缓存', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(title: Text('清空本地缓存')),
          Divider(),
          ListTile(
            title: Text('关于', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(title: Text('StartTooler Mobile v0.14')),
        ],
      ),
    );
  }
}