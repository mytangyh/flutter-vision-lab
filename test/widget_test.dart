import 'package:aicamera/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the technical research baseline', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AiCameraApp());

    expect(find.text('AR 相机识别'), findsOneWidget);
    expect(find.text('技术预研'), findsOneWidget);
    expect(find.textContaining('ML Kit 与 YOLO'), findsOneWidget);
  });
}
