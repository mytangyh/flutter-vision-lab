import 'package:aicamera/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows four research implementations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AiCameraApp());
    await tester.pumpAndSettle();

    expect(find.text('YOLO 端侧识别'), findsOneWidget);
    expect(find.text('YOLO · MNN'), findsOneWidget);
    expect(find.text('ML Kit 物体检测'), findsOneWidget);
    expect(find.text('MNN + 云端精识别'), findsOneWidget);
  });

  testWidgets('builds the application shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      const AiCameraApp(
        home: Scaffold(body: Text('YOLO MVP')),
      ),
    );

    expect(find.text('YOLO MVP'), findsOneWidget);
  });
}
