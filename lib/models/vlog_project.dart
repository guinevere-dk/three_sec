import 'dart:convert';

class VlogProject {
  final String id;
  String title;
  List<String> videoPaths; // 클립 경로 리스트
  Map<String, double> audioConfig; // 클립별 볼륨
  String? bgmPath;
  double bgmVolume;
  String quality; // '720p', '1080p', '4k'
  String folderName; // Added folder support
  DateTime createdAt;
  DateTime updatedAt;

  VlogProject({
    required this.id,
    required this.title,
    required this.videoPaths,
    this.audioConfig = const {},
    this.bgmPath,
    this.bgmVolume = 0.5,
    this.quality = '1080p',
    this.folderName = '기본',
    required this.createdAt,
    required this.updatedAt,
  });

  // JSON -> Object
  factory VlogProject.fromJson(Map<String, dynamic> json) {
    return VlogProject(
      id: json['id'],
      title: json['title'],
      videoPaths: List<String>.from(json['videoPaths'] ?? []),
      audioConfig: Map<String, double>.from(json['audioConfig'] ?? {}),
      bgmPath: json['bgmPath'],
      bgmVolume: (json['bgmVolume'] as num?)?.toDouble() ?? 0.5,
      quality: json['quality'] ?? '1080p',
      folderName: json['folderName'] ?? '기본',
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  // Object -> JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'videoPaths': videoPaths,
      'audioConfig': audioConfig,
      'bgmPath': bgmPath,
      'bgmVolume': bgmVolume,
      'quality': quality,
      'folderName': folderName,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // 사본 생성 (수정 시 불변성 유지)
  VlogProject copyWith({
    String? title,
    List<String>? videoPaths,
    Map<String, double>? audioConfig,
    String? bgmPath,
    double? bgmVolume,
    String? quality,
    String? folderName,
  }) {
    return VlogProject(
      id: id,
      title: title ?? this.title,
      videoPaths: videoPaths ?? this.videoPaths,
      audioConfig: audioConfig ?? this.audioConfig,
      bgmPath: bgmPath ?? this.bgmPath,
      bgmVolume: bgmVolume ?? this.bgmVolume,
      quality: quality ?? this.quality,
      folderName: folderName ?? this.folderName,
      createdAt: createdAt,
      updatedAt: DateTime.now(), // 수정 시 시간 갱신
    );
  }
}
