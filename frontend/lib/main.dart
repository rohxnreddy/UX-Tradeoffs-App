import 'package:flutter/material.dart';
import 'package:frontend/vmaf/vmaf.dart';
import 'package:frontend/IQA/IQA.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UX Trade Off App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _openVMAF(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VmafPlayer()),
    );
  }

  void _openIQA(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const IQAPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("UX Trade Off App")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => _openVMAF(context),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 50),
              ),
              child: const Text("VMAF"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _openIQA(context),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 50),
              ),
              child: const Text("IQA"),
            ),
          ],
        ),
      ),
    );
  }
}