import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/screens/help_feedback_screen.dart';
import 'package:three_s/theme/moa_theme.dart';

void main() {
  testWidgets('Help and feedback starts on help content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildMoaTheme(), home: const HelpFeedbackScreen()),
    );

    expect(find.text('도움말'), findsOneWidget);
    expect(find.text('개발자에게 피드백'), findsOneWidget);
    expect(find.text('MOA 사용 도움말'), findsOneWidget);
    expect(find.text('2초 촬영'), findsOneWidget);
    expect(find.text('라이브러리와 앨범'), findsOneWidget);
    expect(find.text('메일 앱 열기'), findsNothing);
  });

  testWidgets('Feedback choice reveals mail action only after selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildMoaTheme(), home: const HelpFeedbackScreen()),
    );

    await tester.tap(find.text('개발자에게 피드백'));
    await tester.pumpAndSettle();

    expect(find.text('개발자에게 피드백 보내기'), findsOneWidget);
    expect(find.text('메일 앱 열기'), findsOneWidget);
    expect(find.text('MOA 사용 도움말'), findsNothing);
  });
}
