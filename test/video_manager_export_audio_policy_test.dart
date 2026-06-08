import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_s/managers/video_manager.dart';
import 'package:three_s/models/vlog_project.dart';
import 'package:three_s/utils/brightness_adjustment_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoManager manager;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    manager = VideoManager();
    manager.vlogProjects.clear();
  });

  test('indexed original audio volumes preserve duplicate source paths', () {
    final clips = <VlogClip>[
      VlogClip(id: 'clip-1', path: 'same_source.mp4', volume: 0.25),
      VlogClip(id: 'clip-2', path: 'same_source.mp4', volume: 0.75),
    ];

    final indexedVolumes = buildOriginalAudioVolumesByClip(
      clips: clips,
      originalAudioVolume: 0.8,
    );
    final resolvedVolumes = resolveOriginalAudioVolumesByClip(
      clips: clips,
      audioConfig: const <String, double>{'same_source.mp4': 0.6},
      originalAudioVolumes: indexedVolumes,
    );

    expect(indexedVolumes[0], closeTo(0.2, 0.0001));
    expect(indexedVolumes[1], closeTo(0.6, 0.0001));
    expect(resolvedVolumes[0], closeTo(0.2, 0.0001));
    expect(resolvedVolumes[1], closeTo(0.6, 0.0001));
  });

  test('copyProjectToFolder preserves clip-specific brightness data', () async {
    final project = VlogProject(
      id: 'project-1',
      title: 'Project',
      clips: <VlogClip>[
        VlogClip(
          id: 'clip-1',
          path: 'clip_1.mp4',
          brightnessAdjustments: const <String, double>{'brightness': 22},
        ),
        VlogClip(
          id: 'clip-2',
          path: 'clip_2.mp4',
          brightnessAdjustments: const <String, double>{'brightness': -18},
        ),
      ],
      brightnessAdjustmentScope: kBrightnessAdjustmentScopeClipSpecific,
      brightnessAdjustments: const <String, double>{'brightness': 7},
      createdAt: DateTime(2026, 6, 5),
      updatedAt: DateTime(2026, 6, 5),
    );

    await manager.copyProjectToFolder(project, 'Copied');

    final copied = manager.vlogProjects.first;
    expect(
      copied.brightnessAdjustmentScope,
      kBrightnessAdjustmentScopeClipSpecific,
    );
    expect(copied.brightnessAdjustments['brightness'], 7);
    expect(copied.clips[0].brightnessAdjustments['brightness'], 22);
    expect(copied.clips[1].brightnessAdjustments['brightness'], -18);
  });
}
