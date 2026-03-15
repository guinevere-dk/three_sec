import '../utils/quality_policy.dart';

class VlogClip {
  final String id; // Unique ID
  final String path;
  Duration startTime;
  Duration endTime;
  Duration originalDuration; // Added for Trim UI
  double volume;
  int transformRotation90Step;
  bool transformFlipX;
  bool transformFlipY;
  String transformFitMode;
  double transformOffsetX;
  double transformOffsetY;
  double transformScale;
  double transformAngle;
  double playbackSpeed;
  int timelineThumbMetaVersion;
  int timelineThumbDurationMs;
  int timelineThumbCount;
  List<String> timelineThumbPaths;

  VlogClip({
    String? id,
    required this.path,
    this.startTime = Duration.zero,
    this.endTime = Duration.zero,
    this.originalDuration = Duration.zero,
    this.volume = 1.0,
    this.transformRotation90Step = 0,
    this.transformFlipX = false,
    this.transformFlipY = false,
    this.transformFitMode = 'fill',
    this.transformOffsetX = 0.0,
    this.transformOffsetY = 0.0,
    this.transformScale = 1.0,
    this.transformAngle = 0.0,
    this.playbackSpeed = 1.0,
    this.timelineThumbMetaVersion = 0,
    this.timelineThumbDurationMs = 0,
    this.timelineThumbCount = 0,
    this.timelineThumbPaths = const [],
  }) : id = id ?? '${DateTime.now().millisecondsSinceEpoch}_${path.hashCode}';

  factory VlogClip.fromJson(Map<String, dynamic> json) {
    return VlogClip(
      id: json['id'],
      path: json['path'],
      startTime: Duration(milliseconds: json['startTime'] ?? 0),
      endTime: Duration(milliseconds: json['endTime'] ?? 0),
      originalDuration: Duration(milliseconds: json['originalDuration'] ?? 0),
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      transformRotation90Step:
          (json['transformRotation90Step'] as num?)?.toInt() ?? 0,
      transformFlipX: json['transformFlipX'] as bool? ?? false,
      transformFlipY: json['transformFlipY'] as bool? ?? false,
      transformFitMode: (json['transformFitMode'] as String?) ?? 'fill',
      transformOffsetX: (json['transformOffsetX'] as num?)?.toDouble() ?? 0.0,
      transformOffsetY: (json['transformOffsetY'] as num?)?.toDouble() ?? 0.0,
      transformScale: (json['transformScale'] as num?)?.toDouble() ?? 1.0,
      transformAngle: (json['transformAngle'] as num?)?.toDouble() ?? 0.0,
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      timelineThumbMetaVersion:
          (json['timelineThumbMetaVersion'] as num?)?.toInt() ?? 0,
      timelineThumbDurationMs:
          (json['timelineThumbDurationMs'] as num?)?.toInt() ?? 0,
      timelineThumbCount: (json['timelineThumbCount'] as num?)?.toInt() ?? 0,
      timelineThumbPaths:
          (json['timelineThumbPaths'] as List?)?.whereType<String>().toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'startTime': startTime.inMilliseconds,
      'endTime': endTime.inMilliseconds,
      'originalDuration': originalDuration.inMilliseconds,
      'volume': volume,
      'transformRotation90Step': transformRotation90Step,
      'transformFlipX': transformFlipX,
      'transformFlipY': transformFlipY,
      'transformFitMode': transformFitMode,
      'transformOffsetX': transformOffsetX,
      'transformOffsetY': transformOffsetY,
      'transformScale': transformScale,
      'transformAngle': transformAngle,
      'playbackSpeed': playbackSpeed,
      'timelineThumbMetaVersion': timelineThumbMetaVersion,
      'timelineThumbDurationMs': timelineThumbDurationMs,
      'timelineThumbCount': timelineThumbCount,
      'timelineThumbPaths': timelineThumbPaths,
    };
  }

  VlogClip copyWith({
    String? id,
    String? path,
    Duration? startTime,
    Duration? endTime,
    Duration? originalDuration,
    double? volume,
    int? transformRotation90Step,
    bool? transformFlipX,
    bool? transformFlipY,
    String? transformFitMode,
    double? transformOffsetX,
    double? transformOffsetY,
    double? transformScale,
    double? transformAngle,
    double? playbackSpeed,
    int? timelineThumbMetaVersion,
    int? timelineThumbDurationMs,
    int? timelineThumbCount,
    List<String>? timelineThumbPaths,
  }) {
    return VlogClip(
      id: id ?? this.id,
      path: path ?? this.path,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      originalDuration: originalDuration ?? this.originalDuration,
      volume: volume ?? this.volume,
      transformRotation90Step:
          transformRotation90Step ?? this.transformRotation90Step,
      transformFlipX: transformFlipX ?? this.transformFlipX,
      transformFlipY: transformFlipY ?? this.transformFlipY,
      transformFitMode: transformFitMode ?? this.transformFitMode,
      transformOffsetX: transformOffsetX ?? this.transformOffsetX,
      transformOffsetY: transformOffsetY ?? this.transformOffsetY,
      transformScale: transformScale ?? this.transformScale,
      transformAngle: transformAngle ?? this.transformAngle,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      timelineThumbMetaVersion:
          timelineThumbMetaVersion ?? this.timelineThumbMetaVersion,
      timelineThumbDurationMs:
          timelineThumbDurationMs ?? this.timelineThumbDurationMs,
      timelineThumbCount: timelineThumbCount ?? this.timelineThumbCount,
      timelineThumbPaths: timelineThumbPaths ?? this.timelineThumbPaths,
    );
  }
}

class VlogProject {
  static const Object _noChange = Object();

  final String id;
  String title;
  List<VlogClip> clips; // Replaced videoPaths with clips
  Map<String, double>
  audioConfig; // Deprecated, kept for compatibility if needed, or moved to Clip?
  String? bgmPath;
  double bgmVolume;
  String quality; // '720p', '1080p', '4k'
  bool isFavorite;
  String folderName;
  String? ownerAccountId;
  String lockState;
  String? trashedFromFolderName;
  String? cloudProjectId;
  DateTime? cloudSyncedAt;
  String canvasAspectRatioPreset;
  String canvasBackgroundMode;
  DateTime createdAt;
  DateTime updatedAt;

  VlogProject({
    required this.id,
    required this.title,
    required this.clips,
    this.audioConfig = const {},
    this.bgmPath,
    this.bgmVolume = 0.5,
    this.quality = '1080p',
    this.isFavorite = false,
    this.folderName = '기본',
    this.ownerAccountId,
    this.lockState = 'unlocked',
    this.trashedFromFolderName,
    this.cloudProjectId,
    this.cloudSyncedAt,
    this.canvasAspectRatioPreset = 'r9_16',
    this.canvasBackgroundMode = 'crop_fill',
    required this.createdAt,
    required this.updatedAt,
  });

  // JSON -> Object
  factory VlogProject.fromJson(Map<String, dynamic> json) {
    // 1. Handle legacy `videoPaths` (List<String>)
    List<VlogClip> clipsList = [];
    if (json['videoPaths'] != null && (json['videoPaths'] as List).isNotEmpty) {
      final paths = List<String>.from(json['videoPaths']);
      clipsList = paths.map((p) => VlogClip(path: p)).toList();
    }
    // 2. Handle new `clips` (List<VlogClip>)
    else if (json['clips'] != null) {
      clipsList = (json['clips'] as List)
          .map((c) => VlogClip.fromJson(c))
          .toList();
    }

    return VlogProject(
      id: json['id'],
      title: json['title'],
      clips: clipsList,
      audioConfig: Map<String, double>.from(json['audioConfig'] ?? {}),
      bgmPath: json['bgmPath'],
      bgmVolume: (json['bgmVolume'] as num?)?.toDouble() ?? 0.5,
      quality: normalizeExportQuality(json['quality'] as String?),
      isFavorite: json['isFavorite'] as bool? ?? false,
      folderName: json['folderName'] ?? '기본',
      ownerAccountId: json['ownerAccountId'] as String?,
      lockState: json['lockState'] as String? ?? 'unlocked',
      trashedFromFolderName: json['trashedFromFolderName'] as String?,
      cloudProjectId: json['cloudProjectId'] as String?,
      cloudSyncedAt: json['cloudSyncedAt'] != null
          ? DateTime.tryParse(json['cloudSyncedAt'] as String)
          : null,
      canvasAspectRatioPreset:
          json['canvasAspectRatioPreset'] as String? ?? 'r9_16',
      canvasBackgroundMode:
          json['canvasBackgroundMode'] as String? ?? 'crop_fill',
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  // Object -> JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'clips': clips.map((c) => c.toJson()).toList(),
      'audioConfig':
          audioConfig, // Keeping for backward compatibility if needed by native
      'bgmPath': bgmPath,
      'bgmVolume': bgmVolume,
      'quality': quality,
      'isFavorite': isFavorite,
      'folderName': folderName,
      'ownerAccountId': ownerAccountId,
      'lockState': lockState,
      'trashedFromFolderName': trashedFromFolderName,
      'cloudProjectId': cloudProjectId,
      'cloudSyncedAt': cloudSyncedAt?.toIso8601String(),
      'canvasAspectRatioPreset': canvasAspectRatioPreset,
      'canvasBackgroundMode': canvasBackgroundMode,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // 사본 생성 (수정 시 불변성 유지)
  VlogProject copyWith({
    String? title,
    List<VlogClip>? clips,
    Map<String, double>? audioConfig,
    String? bgmPath,
    double? bgmVolume,
    String? quality,
    bool? isFavorite,
    String? folderName,
    String? ownerAccountId,
    String? lockState,
    Object? trashedFromFolderName = _noChange,
    String? cloudProjectId,
    DateTime? cloudSyncedAt,
    String? canvasAspectRatioPreset,
    String? canvasBackgroundMode,
    DateTime? updatedAt,
  }) {
    return VlogProject(
      id: id,
      title: title ?? this.title,
      clips: clips ?? this.clips,
      audioConfig: audioConfig ?? this.audioConfig,
      bgmPath: bgmPath ?? this.bgmPath,
      bgmVolume: bgmVolume ?? this.bgmVolume,
      quality: quality ?? this.quality,
      isFavorite: isFavorite ?? this.isFavorite,
      folderName: folderName ?? this.folderName,
      ownerAccountId: ownerAccountId ?? this.ownerAccountId,
      lockState: lockState ?? this.lockState,
      trashedFromFolderName: identical(trashedFromFolderName, _noChange)
          ? this.trashedFromFolderName
          : trashedFromFolderName as String?,
      cloudProjectId: cloudProjectId ?? this.cloudProjectId,
      cloudSyncedAt: cloudSyncedAt ?? this.cloudSyncedAt,
      canvasAspectRatioPreset:
          canvasAspectRatioPreset ?? this.canvasAspectRatioPreset,
      canvasBackgroundMode: canvasBackgroundMode ?? this.canvasBackgroundMode,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(), // 수정 시 시간 갱신
    );
  }
}
