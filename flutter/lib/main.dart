// lib/main.dart
//
// Flutter Hello demo —— 仅展示一个居中的 "Hello, StartTooler!"。

import 'package:flutter/material.dart';

void main() {
  runApp(const HelloApp());
}

class HelloApp extends StatelessWidget {
  const HelloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hello',
      debugShowCheckedModeBanner: false,
      home: const HelloPage(),
    );
  }
}

class HelloPage extends StatelessWidget {
  const HelloPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hello')),
      body: const Center(
        child: Text(
          'Hello, StartTooler!',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}