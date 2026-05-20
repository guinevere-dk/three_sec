import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/widgets/media_widgets.dart';

void main() {
  testWidgets('cloud-only grid item renders explicit Cloud body', (
    tester,
  ) async {
    var thumbnailRequested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 140,
            height: 140,
            child: MediaWidgets.buildMediaGridItem(
              path: 'cloud_only://album/video/redacted.mp4',
              isSelected: false,
              selectIndex: -1,
              isSelectionMode: false,
              gridColumnCount: 3,
              isFavorite: false,
              benchmarkStyle: true,
              showDurationBadge: true,
              statusBadge: 'Cloud',
              isCloudOnly: true,
              onTap: () {},
              onLongPress: () {},
              getThumbnail: (_) async {
                thumbnailRequested = true;
                return Uint8List(0);
              },
              getDuration: (_) async => const Duration(seconds: 2),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Cloud'), findsOneWidget);
    expect(find.text('길게 눌러 기기로 받기'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_rounded), findsWidgets);
    expect(thumbnailRequested, isFalse);
  });

  testWidgets('cloud-only grid item renders Storage thumbnail bytes', (
    tester,
  ) async {
    var localThumbnailRequested = false;
    var cloudThumbnailRequested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 140,
            height: 140,
            child: MediaWidgets.buildMediaGridItem(
              path: 'cloud_only://album/video/redacted.mp4',
              isSelected: false,
              selectIndex: -1,
              isSelectionMode: false,
              gridColumnCount: 3,
              isFavorite: false,
              benchmarkStyle: true,
              statusBadge: 'Cloud',
              isCloudOnly: true,
              onTap: () {},
              onLongPress: () {},
              getThumbnail: (_) async {
                localThumbnailRequested = true;
                return null;
              },
              getCloudThumbnail: (_) async {
                cloudThumbnailRequested = true;
                return _onePixelPng;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);
    expect(localThumbnailRequested, isFalse);
    expect(cloudThumbnailRequested, isTrue);
  });

  testWidgets(
    'cloud-only grid item falls back when Storage thumbnail is null',
    (tester) async {
      var cloudThumbnailRequested = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 140,
              height: 140,
              child: MediaWidgets.buildMediaGridItem(
                path: 'cloud_only://album/video/redacted.mp4',
                isSelected: false,
                selectIndex: -1,
                isSelectionMode: false,
                gridColumnCount: 3,
                isFavorite: false,
                benchmarkStyle: true,
                statusBadge: 'Cloud',
                isCloudOnly: true,
                onTap: () {},
                onLongPress: () {},
                getThumbnail: (_) async => null,
                getCloudThumbnail: (_) async {
                  cloudThumbnailRequested = true;
                  return null;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Cloud'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_rounded), findsWidgets);
      expect(cloudThumbnailRequested, isTrue);
    },
  );

  testWidgets('local grid item still uses local thumbnail loader', (
    tester,
  ) async {
    var localThumbnailRequested = false;
    var cloudThumbnailRequested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 140,
            height: 140,
            child: MediaWidgets.buildMediaGridItem(
              path: 'local/redacted.mp4',
              isSelected: false,
              selectIndex: -1,
              isSelectionMode: false,
              gridColumnCount: 3,
              isFavorite: false,
              benchmarkStyle: true,
              statusBadge: '기기',
              isCloudOnly: false,
              onTap: () {},
              onLongPress: () {},
              getThumbnail: (_) async {
                localThumbnailRequested = true;
                return _onePixelPng;
              },
              getCloudThumbnail: (_) async {
                cloudThumbnailRequested = true;
                return _onePixelPng;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(localThumbnailRequested, isTrue);
    expect(cloudThumbnailRequested, isFalse);
  });
}

final Uint8List _onePixelPng = Uint8List.fromList(const <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
