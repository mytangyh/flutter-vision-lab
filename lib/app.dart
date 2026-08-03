import 'package:aicamera/features/home/research_home_page.dart';
import 'package:flutter/material.dart';

class AiCameraApp extends StatelessWidget {
  const AiCameraApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AR 相机识别',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C5CFC),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: home ?? const ResearchHomePage(),
    );
  }
}
