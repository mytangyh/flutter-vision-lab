import 'package:flutter/material.dart';

void main() {
  runApp(const AiCameraApp());
}

class AiCameraApp extends StatelessWidget {
  const AiCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AR 相机识别',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ResearchHomePage(),
    );
  }
}

class ResearchHomePage extends StatelessWidget {
  const ResearchHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AR 相机识别')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.center_focus_strong, size: 72),
              SizedBox(height: 20),
              Text(
                '技术预研',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 12),
              Text(
                '后续将在同一套相机输入上对比 ML Kit 与 YOLO 的检测效果。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
