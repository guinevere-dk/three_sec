// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_s/managers/video_manager.dart';
import 'package:three_s/screens/library_screen.dart';

class _FirebaseCoreBucketMock implements TestFirebaseCoreHostApi {
  CoreInitializeResponse _response(String name) {
    return CoreInitializeResponse(
      name: name,
      options: CoreFirebaseOptions(
        apiKey: 'test',
        appId: '1:123456789:android:123456789',
        messagingSenderId: '123456789',
        projectId: 'test-project',
        storageBucket: 'test-project.appspot.com',
      ),
      pluginConstants: const {},
    );
  }

  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async {
    return _response(appName);
  }

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    return <CoreInitializeResponse>[_response(defaultFirebaseAppName)];
  }

  @override
  Future<CoreFirebaseOptions> optionsFromResource() async {
    return _response(defaultFirebaseAppName).options;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    TestFirebaseCoreHostApi.setUp(_FirebaseCoreBucketMock());
    try {
      await Firebase.initializeApp();
    } on FirebaseException catch (error) {
      if (error.code != 'duplicate-app') rethrow;
    }
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  Future<void> pumpLibraryScreen(
    WidgetTester tester,
    VideoManager manager,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<VideoManager>.value(
        value: manager,
        child: MaterialApp(
          home: LibraryScreen(
            keyPickMedia: GlobalKey(),
            keyAlbumGridItem: GlobalKey(),
            keyFirstClip: GlobalKey(),
            keyCreateProject: GlobalKey(),
            onRefreshData: () {},
            onMerge: (_) {},
            onPickMedia: (_) {},
            isActive: true,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'library detail shows loading instead of zero before album load completes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final documentsDirectory = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return documentsDirectory.future;
            }
            return null;
          });

      final manager = VideoManager()
        ..recordedVideoPaths = <String>[]
        ..clipAlbums = <String>['일상', '고덕스테이', '휴지통']
        ..albumCounts = <String, int>{'일상': 7, '고덕스테이': 15, '휴지통': 1}
        ..albumLocalCounts = <String, int>{'일상': 7, '고덕스테이': 15, '휴지통': 1};

      try {
        await pumpLibraryScreen(tester, manager);

        await tester.tap(find.text('고덕스테이'));
        await tester.pump();

        expect(find.text('고덕스테이 15'), findsOneWidget);
        expect(find.text('15 Clips'), findsOneWidget);
        expect(find.text('0 Clips'), findsNothing);
        expect(find.textContaining('No clips.'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'library detail handles fixed-length recorded paths before album load',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final documentsDirectory = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return documentsDirectory.future;
            }
            return null;
          });

      final manager = VideoManager()
        ..recordedVideoPaths = List<String>.filled(
          1,
          'C:\\tmp\\vlogs\\raw_clips\\일상\\stale.mp4',
        )
        ..clipAlbums = <String>['일상', '고덕스테이', '휴지통']
        ..albumCounts = <String, int>{'일상': 7, '고덕스테이': 15, '휴지통': 1}
        ..albumLocalCounts = <String, int>{'일상': 7, '고덕스테이': 15, '휴지통': 1};

      try {
        await pumpLibraryScreen(tester, manager);

        await tester.tap(find.text('고덕스테이'));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('고덕스테이 15'), findsOneWidget);
        expect(find.text('15 Clips'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('library detail keeps folder count after album load completes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final documentsDirectory = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documentsDirectory.future;
          }
          return null;
        });
    final loadedPaths = List<String>.generate(
      15,
      (index) => 'C:\\tmp\\vlogs\\raw_clips\\고덕스테이\\clip_$index.mp4',
    );
    final manager = VideoManager()
      ..recordedVideoPaths = <String>[]
      ..clipAlbums = <String>['일상', '고덕스테이', '휴지통']
      ..albumCounts = <String, int>{'일상': 7, '고덕스테이': 15, '휴지통': 1}
      ..albumLocalCounts = <String, int>{'일상': 7, '고덕스테이': 15, '휴지통': 1};

    try {
      await pumpLibraryScreen(tester, manager);

      await tester.tap(find.text('고덕스테이'));
      await tester.pump();
      manager.recordedVideoPaths = loadedPaths;
      manager.albumCounts = <String, int>{
        ...manager.albumCounts,
        '고덕스테이': loadedPaths.length,
      };
      manager.albumLocalCounts = <String, int>{
        ...manager.albumLocalCounts,
        '고덕스테이': loadedPaths.length,
      };
      manager.notifyListeners();
      await tester.pump();

      expect(manager.recordedVideoPaths, hasLength(15));
      expect(manager.albumCounts['고덕스테이'], 15);
      expect(manager.albumLocalCounts['고덕스테이'], 15);
      expect(find.text('고덕스테이 15'), findsOneWidget);
      expect(find.text('15 Clips'), findsOneWidget);
      expect(find.text('0 Clips'), findsNothing);
      expect(find.textContaining('No clips.'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
