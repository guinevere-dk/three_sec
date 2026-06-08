import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_s/managers/user_status_manager.dart';
import 'package:three_s/managers/video_manager.dart';
import 'package:three_s/models/vlog_project.dart';
import 'package:three_s/screens/video_edit_screen.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeVideoPlayerPlatform platform;
  late Directory tempDir;

  setUp(() async {
    platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await UserStatusManager().setTier(
      UserTier.standard,
      productId: '3s_standard_monthly',
      purchaseDate: DateTime(2026, 6, 4),
    );
    tempDir = Directory.systemTemp.createTempSync(
      'video_edit_preview_playback_',
    );
  });

  tearDown(() async {
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('ALL preview advances from the first clip to the second clip', (
    tester,
  ) async {
    final project = _buildProject(tempDir, clipCount: 2);

    await _pumpEditScreen(tester, project);
    await _openSoundPanel(tester);
    await _selectAllPlayback(tester);

    final firstPlayerId = platform.lastPlayedPlayerId;
    expect(firstPlayerId, isNotNull);

    platform.complete(firstPlayerId!);
    await _drainAsyncWork(
      tester,
      until: () =>
          platform.playedPlayerIds.any((id) => id != firstPlayerId) &&
          find.text('현재 2 / 2').evaluate().isNotEmpty,
    );

    expect(
      platform.playedPlayerIds.any((id) => id != firstPlayerId),
      isTrue,
      reason: 'ALL preview should start clip 2 after clip 1 completes.',
    );
    expect(find.text('현재 2 / 2'), findsOneWidget);
  });

  testWidgets('ALL preview advances while trim mode is active', (tester) async {
    final project = _buildProject(tempDir, clipCount: 2);

    await _pumpEditScreen(tester, project);
    await _selectAllPlayback(tester);
    await _openToolbarMode(tester, 'Trim');

    final firstPlayerId = platform.lastPlayedPlayerId;
    expect(firstPlayerId, isNotNull);

    platform.complete(firstPlayerId!);
    await _drainAsyncWork(
      tester,
      until: () =>
          platform.playedPlayerIds.any((id) => id != firstPlayerId) &&
          find.text('현재 2 / 2').evaluate().isNotEmpty,
    );

    expect(
      platform.playedPlayerIds.any((id) => id != firstPlayerId),
      isTrue,
      reason: 'ALL preview should advance even while Trim is open.',
    );
    expect(find.text('현재 2 / 2'), findsOneWidget);
  });

  testWidgets('ALL preview advances while brightness mode is active', (
    tester,
  ) async {
    final project = _buildProject(tempDir, clipCount: 2);

    await _pumpEditScreen(tester, project);
    await _selectAllPlayback(tester);
    await _openToolbarMode(tester, '밝기');
    expect(find.text('노출'), findsOneWidget);

    final firstPlayerId = platform.lastPlayedPlayerId;
    expect(firstPlayerId, isNotNull);

    platform.complete(firstPlayerId!);
    await _drainAsyncWork(
      tester,
      until: () =>
          platform.playedPlayerIds.any((id) => id != firstPlayerId) &&
          find.text('현재 2 / 2').evaluate().isNotEmpty,
    );

    expect(
      platform.playedPlayerIds.any((id) => id != firstPlayerId),
      isTrue,
      reason: 'ALL preview should advance during brightness adjustments.',
    );
    expect(find.text('현재 2 / 2'), findsOneWidget);
  });

  testWidgets(
    'ALL preview with one clip stops without requesting another clip',
    (tester) async {
      final project = _buildProject(tempDir, clipCount: 1);

      await _pumpEditScreen(tester, project);
      await _openSoundPanel(tester);
      await _selectAllPlayback(tester);

      final firstPlayerId = platform.lastPlayedPlayerId;
      expect(firstPlayerId, isNotNull);

      platform.complete(firstPlayerId!);
      await _drainAsyncWork(
        tester,
        until: () =>
            platform.createdPlayerIds.isNotEmpty &&
            !platform.createdPlayerIds.contains(firstPlayerId) &&
            find.text('현재 1 / 1').evaluate().isNotEmpty,
      );

      expect(
        platform.playedPlayerIds.where((id) => id != firstPlayerId),
        isEmpty,
      );
      expect(find.text('현재 1 / 1'), findsOneWidget);
    },
  );

  testWidgets('CLIP preview still stops on the current clip', (tester) async {
    final project = _buildProject(tempDir, clipCount: 2);

    await _pumpEditScreen(tester, project);
    await _openSoundPanel(tester);

    final firstPlayerId = platform.lastPlayedPlayerId;
    expect(firstPlayerId, isNotNull);

    platform.complete(firstPlayerId!);
    await _drainAsyncWork(
      tester,
      until: () => find.text('현재 1 / 2').evaluate().isNotEmpty,
    );

    expect(
      platform.playedPlayerIds.where((id) => id != firstPlayerId),
      isEmpty,
      reason: 'CLIP preview should not start clip 2 automatically.',
    );
    expect(find.text('현재 1 / 2'), findsOneWidget);
  });

  testWidgets('sound panel labels original clip audio and bgm separately', (
    tester,
  ) async {
    final project = _buildProject(tempDir, clipCount: 2);

    await _pumpEditScreen(tester, project);
    await _openSoundPanel(tester);

    expect(find.text('원본 사운드'), findsOneWidget);
    expect(find.text('BGM 사운드'), findsOneWidget);
    expect(find.text('클립 사운드'), findsNothing);
  });

  testWidgets('sound sliders keep active and reloaded clip playback muted', (
    tester,
  ) async {
    final project = _buildProject(tempDir, clipCount: 2);

    await _pumpEditScreen(tester, project);
    await _openSoundPanel(tester);

    final firstPlayerId = platform.lastPlayedPlayerId;
    expect(firstPlayerId, isNotNull);

    final sliders = find.byWidgetPredicate(
      (widget) => widget is Slider && widget.max == 1,
    );
    expect(sliders, findsNWidgets(2));
    tester.widget<Slider>(sliders.at(0)).onChanged!(0);
    tester.widget<Slider>(sliders.at(0)).onChangeEnd!(0);
    await tester.pump();

    expect(
      platform.lastVolumeFor(firstPlayerId!),
      0,
      reason: 'Muting original audio should mute the active video controller.',
    );

    await tester.tap(find.byTooltip('다음 클립'));
    await _drainAsyncWork(
      tester,
      until: () =>
          find.text('현재 2 / 2').evaluate().isNotEmpty &&
          platform.createdPlayerIds.any((id) => id != firstPlayerId),
    );

    final secondPlayerId = platform.createdPlayerIds.last;
    expect(secondPlayerId, isNot(firstPlayerId));
    expect(
      platform.lastVolumeFor(secondPlayerId),
      0,
      reason:
          'A newly loaded clip controller must inherit the muted original '
          'audio slider value.',
    );
  });

  testWidgets('brightness adjustments stay scoped to selected clip', (
    tester,
  ) async {
    final project = _buildProject(tempDir, clipCount: 2);

    await _pumpEditScreen(tester, project);
    await _openToolbarMode(tester, '밝기');

    final panelRect = tester.getRect(
      find.byKey(const ValueKey('panel_brightness')),
    );
    await tester.tapAt(
      Offset(panelRect.left + (panelRect.width * 0.75), panelRect.bottom - 20),
    );
    await tester.pump();

    expect(find.text('57'), findsOneWidget);

    await tester.tap(find.byTooltip('다음 클립'));
    await _drainAsyncWork(
      tester,
      until: () => find.text('현재 2 / 2').evaluate().isNotEmpty,
    );

    expect(
      find.text('밝기'),
      findsOneWidget,
      reason: 'Clip 2 should keep default brightness after clip 1 changes.',
    );
    expect(find.text('57'), findsNothing);

    await tester.tap(find.byTooltip('이전 클립'));
    await _drainAsyncWork(
      tester,
      until: () => find.text('현재 1 / 2').evaluate().isNotEmpty,
    );

    expect(
      find.text('57'),
      findsOneWidget,
      reason: 'Returning to clip 1 should restore its own brightness value.',
    );
  });

  testWidgets(
    'tap selected trim timeline center seeks preview to middle frame',
    (tester) async {
      final project = _buildProject(tempDir, clipCount: 1);

      await _pumpEditScreen(tester, project);
      await _openToolbarMode(tester, 'Trim');

      final playerId = platform.lastPlayedPlayerId;
      expect(playerId, isNotNull);

      final trackRect = _selectedTrimTimelineRect(tester);
      platform.clearSeekHistory(playerId!);
      await tester.tapAt(trackRect.center);
      await tester.pump();
      await _drainAsyncWork(
        tester,
        until: () => platform.positionFor(playerId).inMilliseconds >= 900,
      );
      final playheadRect = _selectedTrimTimelinePlayheadRect(tester);

      expect(
        platform.seekHistoryFor(playerId),
        isNotEmpty,
        reason:
            'Tapping the selected trim timeline should issue a preview seek.',
      );
      expect(
        platform.positionFor(playerId).inMilliseconds,
        inInclusiveRange(900, 1200),
        reason:
            'Tapping the selected trim timeline center should show the '
            'middle frame, not leave the preview at the start frame.',
      );
      expect(
        playheadRect.center.dx,
        closeTo(trackRect.center.dx, 2),
        reason:
            'The white trim playhead should follow the tapped timeline '
            'position.',
      );
      expect(find.text('0:01 / 0:02'), findsOneWidget);
    },
  );

  testWidgets('tap selected trim timeline edges clamps preview to trim range', (
    tester,
  ) async {
    final project = _buildProject(
      tempDir,
      clipCount: 1,
      clipStart: const Duration(milliseconds: 300),
      clipEnd: const Duration(milliseconds: 1800),
    );

    await _pumpEditScreen(tester, project);
    await _openToolbarMode(tester, 'Trim');

    final playerId = platform.lastPlayedPlayerId;
    expect(playerId, isNotNull);

    final trackRect = _selectedTrimTimelineRect(tester);
    platform.clearSeekHistory(playerId!);
    await tester.tapAt(Offset(trackRect.right - 14, trackRect.center.dy));
    await tester.pump();
    await _drainAsyncWork(
      tester,
      until: () => platform.positionFor(playerId).inMilliseconds >= 1700,
    );

    expect(
      platform.positionFor(playerId).inMilliseconds,
      inInclusiveRange(1700, 1800),
      reason:
          'Tapping near the selected trim timeline end should stay inside '
          'the clip trim range.',
    );
  });

  testWidgets('drag selected trim start handle still trims start', (
    tester,
  ) async {
    final project = _buildProject(tempDir, clipCount: 1);

    await _pumpEditScreen(tester, project);
    await _openToolbarMode(tester, 'Trim');

    final trackRect = _selectedTrimTimelineRect(tester);
    await tester.dragFrom(
      Offset(trackRect.left + 1, trackRect.center.dy),
      const Offset(70, 0),
    );
    await tester.pump();
    await _drainAsyncWork(
      tester,
      until: () => project.clips.single.startTime.inMilliseconds >= 350,
    );

    expect(
      project.clips.single.startTime.inMilliseconds,
      greaterThanOrEqualTo(350),
      reason: 'The start handle should keep its drag behavior above tap layer.',
    );
  });

  testWidgets('drag selected trim end handle still trims end', (tester) async {
    final project = _buildProject(tempDir, clipCount: 1);

    await _pumpEditScreen(tester, project);
    await _openToolbarMode(tester, 'Trim');

    final trackRect = _selectedTrimTimelineRect(tester);
    await tester.dragFrom(
      Offset(trackRect.right - 1, trackRect.center.dy),
      const Offset(-70, 0),
    );
    await tester.pump();
    await _drainAsyncWork(
      tester,
      until: () => project.clips.single.endTime.inMilliseconds <= 1750,
    );

    expect(
      project.clips.single.endTime.inMilliseconds,
      lessThanOrEqualTo(1750),
      reason: 'The end handle should keep its drag behavior above tap layer.',
    );
  });

  testWidgets('drag selected trim playhead still scrubs preview', (
    tester,
  ) async {
    final project = _buildProject(tempDir, clipCount: 1);

    await _pumpEditScreen(tester, project);
    await _openToolbarMode(tester, 'Trim');

    final playerId = platform.lastPlayedPlayerId;
    expect(playerId, isNotNull);

    final trackRect = _selectedTrimTimelineRect(tester);
    await tester.tapAt(trackRect.center);
    await tester.pump();
    await _drainAsyncWork(
      tester,
      until: () => platform.positionFor(playerId!).inMilliseconds >= 900,
    );

    final playheadBefore = _selectedTrimTimelinePlayheadRect(tester);
    platform.clearSeekHistory(playerId!);
    await tester.dragFrom(playheadBefore.center, const Offset(60, 0));
    await tester.pump();
    await _drainAsyncWork(
      tester,
      until: () => platform.positionFor(playerId).inMilliseconds >= 1300,
    );
    final playheadAfter = _selectedTrimTimelinePlayheadRect(tester);

    expect(
      platform.seekHistoryFor(playerId),
      isNotEmpty,
      reason: 'Dragging the white playhead should still issue preview seeks.',
    );
    expect(
      playheadAfter.center.dx,
      greaterThan(playheadBefore.center.dx + 40),
      reason: 'The white playhead drag should remain above the tap layer.',
    );
  });
}

VlogProject _buildProject(
  Directory tempDir, {
  required int clipCount,
  Duration clipStart = Duration.zero,
  Duration clipEnd = const Duration(milliseconds: 2100),
}) {
  final clips = <VlogClip>[];
  for (var i = 0; i < clipCount; i++) {
    final file = File('${tempDir.path}${Platform.pathSeparator}clip_$i.mp4');
    file.writeAsBytesSync(<int>[0, 1, 2, 3], flush: true);
    clips.add(
      VlogClip(
        id: 'clip-$i',
        path: file.path,
        startTime: clipStart,
        endTime: clipEnd,
        originalDuration: const Duration(milliseconds: 2100),
      ),
    );
  }

  return VlogProject(
    id: 'project-preview-test-$clipCount',
    title: 'Preview test',
    clips: clips,
    createdAt: DateTime(2026, 6, 4),
    updatedAt: DateTime(2026, 6, 4),
  );
}

Future<void> _pumpEditScreen(WidgetTester tester, VlogProject project) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(430, 932);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<VideoManager>.value(value: VideoManager()),
        Provider<UserStatusManager>.value(value: UserStatusManager()),
      ],
      child: MaterialApp(home: VideoEditScreen(project: project)),
    ),
  );
  await _drainAsyncWork(
    tester,
    until: () =>
        find.text('현재 1 / ${project.clips.length}').evaluate().isNotEmpty,
  );
  expect(find.text('현재 1 / ${project.clips.length}'), findsOneWidget);
}

Future<void> _openSoundPanel(WidgetTester tester) async {
  await _openToolbarMode(tester, '사운드');
  expect(find.text('원본 사운드'), findsOneWidget);
}

Future<void> _openToolbarMode(WidgetTester tester, String label) async {
  final toolbarButton = find.bySemanticsLabel(label);
  if (toolbarButton.evaluate().isEmpty) {
    await tester.drag(find.byType(ListView).last, const Offset(-260, 0));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(toolbarButton, findsWidgets);
  await tester.tap(toolbarButton.first);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 1),
  );
}

Future<void> _selectAllPlayback(WidgetTester tester) async {
  await tester.tap(find.text('CLIP'));
  await tester.pump(const Duration(milliseconds: 50));
  expect(find.text('ALL'), findsOneWidget);
}

Rect _selectedTrimTimelineRect(WidgetTester tester) {
  final selectedTimelineTapTarget = _selectedTrimTimelineTapTarget();
  expect(selectedTimelineTapTarget, findsOneWidget);
  return tester.getRect(selectedTimelineTapTarget);
}

Finder _selectedTrimTimelineTapTarget() {
  return find.byKey(const ValueKey('selected_trim_timeline_tap_target'));
}

Rect _selectedTrimTimelinePlayheadRect(WidgetTester tester) {
  final selectedTimelinePlayhead = find.byKey(
    const ValueKey('selected_trim_timeline_playhead'),
  );
  expect(selectedTimelinePlayhead, findsOneWidget);
  return tester.getRect(selectedTimelinePlayhead);
}

Future<void> _drainAsyncWork(
  WidgetTester tester, {
  required bool Function() until,
}) async {
  for (var i = 0; i < 20; i++) {
    if (until()) return;
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, _FakeVideoPlayer> _players = <int, _FakeVideoPlayer>{};
  final List<int> playedPlayerIds = <int>[];
  int _nextPlayerId = 1;

  List<int> get createdPlayerIds => _players.keys.toList(growable: false);
  int? get lastPlayedPlayerId =>
      playedPlayerIds.isEmpty ? null : playedPlayerIds.last;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final playerId = _nextPlayerId++;
    final player = _FakeVideoPlayer(
      duration: const Duration(milliseconds: 2100),
    );
    _players[playerId] = player;
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final player = _players[playerId]!;
    return Stream<VideoEvent>.multi((controller) {
      controller.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: player.duration,
          size: const Size(1080, 1920),
        ),
      );
      final subscription = player.events.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<void> dispose(int playerId) async {
    final player = _players.remove(playerId);
    await player?.events.close();
  }

  @override
  Future<void> play(int playerId) async {
    final player = _players[playerId]!;
    playedPlayerIds.add(playerId);
    player.playCount++;
    player.isPlaying = true;
    player.events.add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: true,
      ),
    );
  }

  @override
  Future<void> pause(int playerId) async {
    final player = _players[playerId]!;
    player.isPlaying = false;
    if (!player.events.isClosed) {
      player.events.add(
        VideoEvent(
          eventType: VideoEventType.isPlayingStateUpdate,
          isPlaying: false,
        ),
      );
    }
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    final player = _players[playerId]!;
    player.position = position;
    player.seekedPositions.add(position);
  }

  @override
  Future<Duration> getPosition(int playerId) async {
    return _players[playerId]!.position;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {
    final player = _players[playerId]!;
    player.volume = volume;
    player.volumeHistory.add(volume);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) {
    return ColoredBox(
      color: Colors.black,
      child: Center(child: Text('player-${options.playerId}')),
    );
  }

  void complete(int playerId) {
    final player = _players[playerId]!;
    player.position = player.duration;
    player.isPlaying = false;
    player.events.add(VideoEvent(eventType: VideoEventType.completed));
  }

  void clearSeekHistory(int playerId) {
    _players[playerId]!.seekedPositions.clear();
  }

  Duration positionFor(int playerId) => _players[playerId]!.position;

  List<Duration> seekHistoryFor(int playerId) =>
      _players[playerId]!.seekedPositions.toList(growable: false);

  int playCount(int playerId) => _players[playerId]?.playCount ?? 0;

  double? lastVolumeFor(int playerId) => _players[playerId]?.volume;
}

class _FakeVideoPlayer {
  _FakeVideoPlayer({required this.duration});

  final Duration duration;
  final StreamController<VideoEvent> events =
      StreamController<VideoEvent>.broadcast();
  Duration position = Duration.zero;
  bool isPlaying = false;
  double? volume;
  int playCount = 0;
  final List<Duration> seekedPositions = <Duration>[];
  final List<double> volumeHistory = <double>[];
}
