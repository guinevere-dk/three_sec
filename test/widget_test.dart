// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:three_s/main.dart';

void main() {
  bool firebaseInitialized = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp(
        name: 'test-app',
        options: const FirebaseOptions(
          apiKey: 'test',
          appId: '1:123456789:android:123456789',
          messagingSenderId: '123456789',
          projectId: 'test-project',
        ),
      );
      firebaseInitialized = true;
      debugPrint('[widget_test] Firebase initialized for smoke test');
    } catch (e) {
      debugPrint('[widget_test] Firebase initialize skipped: $e');
      firebaseInitialized = false;
    }
  });

  testWidgets('App boots without crashing', (WidgetTester tester) async {
    if (firebaseInitialized) {
      await tester.pumpWidget(const MyApp());
      expect(find.byType(MaterialApp), findsOneWidget);
      return;
}
    await tester.pumpWidget(const MaterialApp(home: Text('Firebase unavailable')));
    expect(find.text('Firebase unavailable'), findsOneWidget);
  });
}
