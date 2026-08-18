import 'package:flutter/material.dart';

void main() {
  runApp(const StartToolerApp());
}

class StartToolerApp extends StatelessWidget {
  const StartToolerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StartTooler',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HelloPage(),
    );
  }
}

class HelloPage extends StatelessWidget {
  const HelloPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('StartTooler'),
      ),
      body: const Center(
        child: Text(
          'hello!',
          style: TextStyle(fontSize: 48, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
