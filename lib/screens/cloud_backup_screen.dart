import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../managers/user_status_manager.dart';
import '../managers/video_manager.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import 'subscription_management_screen.dart';

class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({super.key});

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends State<CloudBackupScreen> {
  final AuthService _authService = AuthService();
  final CloudService _cloudService = CloudService();
  final UserStatusManager _userStatusManager = UserStatusManager();

  List<VideoMetadata> _videos = const <VideoMetadata>[];
  final Set<String> _selectedVideoIds = <String>{};
  final Set<String> _downloadingVideoIds = <String>{};
  bool _isLoading = true;
  String? _loadError;

  bool get _isAllowed =>
      !_authService.isGuest && _userStatusManager.canReadExistingCloudClips();

  bool get _isGraceReadOnly => _userStatusManager.isInCloudReadGrace();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _userStatusManager.initialize();
    await _loadVideos();
  }

  Future<void> _loadVideos() async {
    if (!_isAllowed) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _videos = const <VideoMetadata>[];
        _loadError = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final videos = await _cloudService.getCompletedUserVideos(
        includeTrash: true,
      );
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _selectedVideoIds.removeWhere(
          (id) => !videos.any((video) => video.videoId == id),
        );
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Cloud 보관함을 불러오지 못했습니다.';
        _isLoading = false;
      });
    }
  }

  Future<void> _openSubscriptionManagement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubscriptionManagementScreen()),
    );
    await _userStatusManager.initialize();
    await _loadVideos();
  }

  void _toggleSelection(String videoId) {
    setState(() {
      if (_selectedVideoIds.contains(videoId)) {
        _selectedVideoIds.remove(videoId);
      } else {
        _selectedVideoIds.add(videoId);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedVideoIds.length == _videos.length) {
        _selectedVideoIds.clear();
      } else {
        _selectedVideoIds
          ..clear()
          ..addAll(_videos.map((video) => video.videoId));
      }
    });
  }

  Future<void> _downloadSelected() async {
    final targets = _videos
        .where((video) => _selectedVideoIds.contains(video.videoId))
        .toList(growable: false);
    if (targets.isEmpty || _downloadingVideoIds.isNotEmpty) return;

    var success = 0;
    var failed = 0;
    final videoManager = context.read<VideoManager>();

    setState(() {
      _downloadingVideoIds.addAll(targets.map((video) => video.videoId));
    });

    for (final video in targets) {
      try {
        final albumName = video.albumName.trim().isEmpty
            ? videoManager.currentAlbum
            : video.albumName.trim();
        final fileName = video.fileName.trim().isEmpty
            ? '${video.videoId}.mp4'
            : video.fileName.trim();
        final restoredPath = await videoManager
            .findExistingCloudRestoredClipPath(
              fileName: fileName,
              fileSize: video.fileSize,
            );
        if (restoredPath != null) {
          final movedFromCloud = await _cloudService.markVideoMovedToDevice(
            video.videoId,
          );
          if (!movedFromCloud) {
            failed++;
            continue;
          }
          await videoManager.registerCloudMovedToDeviceClip(
            path: restoredPath,
            albumName: albumName,
            cloudMetadata: video,
          );
          success++;
          continue;
        }

        final localPath = await videoManager.buildUniqueRawClipPath(
          albumName: albumName,
          fileName: fileName,
        );

        final ok = await _cloudService.downloadVideo(
          videoId: video.videoId,
          localPath: localPath,
        );
        if (!ok || !await File(localPath).exists()) {
          failed++;
          continue;
        }

        final movedFromCloud = await _cloudService.markVideoMovedToDevice(
          video.videoId,
        );
        if (!movedFromCloud) {
          final downloadedFile = File(localPath);
          if (await downloadedFile.exists()) {
            await downloadedFile.delete();
          }
          failed++;
          continue;
        }

        await videoManager.registerCloudMovedToDeviceClip(
          path: localPath,
          albumName: albumName,
          cloudMetadata: video,
        );
        success++;
      } catch (_) {
        failed++;
      } finally {
        if (mounted) {
          setState(() {
            _downloadingVideoIds.remove(video.videoId);
          });
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _selectedVideoIds.clear();
      _downloadingVideoIds.clear();
    });
    await _loadVideos();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('복원 완료 $success개, 실패 $failed개')));
  }

  @override
  Widget build(BuildContext context) {
    final title = _selectedVideoIds.isEmpty
        ? 'Cloud 보관함'
        : '${_selectedVideoIds.length}개 선택됨';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_isAllowed && _videos.isNotEmpty)
            TextButton(onPressed: _toggleSelectAll, child: const Text('전체')),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _isAllowed && _selectedVideoIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _downloadingVideoIds.isEmpty
                  ? _downloadSelected
                  : null,
              icon: _downloadingVideoIds.isEmpty
                  ? const Icon(Icons.download_rounded)
                  : const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
              label: const Text('이 기기에 복원'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (!_isAllowed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 58,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(height: 14),
              Text(
                _authService.isGuest
                    ? '게스트 모드에서는 Cloud 보관함을 사용할 수 없습니다.'
                    : _cloudService.subscriptionExpiredCloudReadMessage(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _openSubscriptionManagement,
                child: Text(
                  _authService.isGuest ? '로그인/구독 안내 보기' : '구독 관리로 이동',
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final graceEndsAt = _userStatusManager.cloudReadGraceEndsAt;

    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _loadVideos, child: const Text('다시 시도')),
          ],
        ),
      );
    }

    if (_videos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadVideos,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Icon(Icons.cloud_done_rounded, size: 58, color: Color(0xFF94A3B8)),
            SizedBox(height: 14),
            Center(child: Text('Cloud 보관함에 완료된 클립이 없습니다.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadVideos,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
        itemCount: _videos.length + (_isGraceReadOnly ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (_isGraceReadOnly && index == 0) {
            return _buildGraceReadOnlyBanner(graceEndsAt);
          }

          final videoIndex = _isGraceReadOnly ? index - 1 : index;
          return _buildVideoTile(_videos[videoIndex]);
        },
      ),
    );
  }

  Widget _buildGraceReadOnlyBanner(DateTime? graceEndsAt) {
    final graceText = graceEndsAt == null
        ? ''
        : ' ${DateFormat('yyyy.MM.dd').format(graceEndsAt)}까지';
    return Card(
      color: const Color(0xFFFFFBEB),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          '구독이 만료되어 신규 Cloud 업로드/복사는 중지되었어요. '
          '기존 Cloud 클립은$graceText 이 기기에 복원할 수 있어요. '
          '구독 복원 또는 재구독 후 Cloud 이용이 다시 가능해요.',
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF92400E),
            height: 1.35,
          ),
        ),
      ),
    );
  }

  Widget _buildVideoTile(VideoMetadata video) {
    final selected = _selectedVideoIds.contains(video.videoId);
    final downloading = _downloadingVideoIds.contains(video.videoId);
    final createdAt = video.completedAt ?? video.createdAt;
    final dateText = createdAt == null
        ? '날짜 없음'
        : DateFormat('yyyy.MM.dd HH:mm').format(createdAt);
    final album = video.albumName.trim().isEmpty ? '기본 앨범' : video.albumName;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: downloading ? null : () => _toggleSelection(video.videoId),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: downloading
                    ? const Padding(
                        padding: EdgeInsets.all(15),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.cloud_done_rounded,
                        color: Color(0xFF2BADEE),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.fileName.isEmpty ? video.videoId : video.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$album · ${video.fileSizeText} · $dateText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: selected
                    ? const Color(0xFF2BADEE)
                    : const Color(0xFFCBD5E1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
