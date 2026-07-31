import 'package:aicamera/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('builds the application shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      const AiCameraApp(
        home: Scaffold(body: Text('YOLO MVP')),
      ),
    );

    expect(find.text('YOLO MVP'), findsOneWidget);
  });
}
