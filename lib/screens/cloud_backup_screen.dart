import 'dart:io';
import 'package:flutter/material.dart';
import '../services/cloud_service.dart';
import '../managers/user_status_manager.dart';
import 'paywall_screen.dart';

/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// 🌩️ 클라우드 백업 화면
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// Standard 등급 이상의 핵심 혜택
/// - 영상 클라우드 백업
/// - 앨범별 관리
/// - 실시간 동기화

class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({super.key});

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends State<CloudBackupScreen> {
  final CloudService _cloudService = CloudService();
  final UserStatusManager _userStatusManager = UserStatusManager();

  String? _selectedAlbum;

  @override
  Widget build(BuildContext context) {
    // Standard 등급 이상만 접근 가능
    if (!_userStatusManager.isStandardOrAbove()) {
      return _buildUpgradeScreen();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('클라우드 백업', style: TextStyle(color: Colors.white)),
        actions: [
          // 사용량 표시
          FutureBuilder<double>(
            future: _cloudService.getStorageUsageRatio(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              
              final ratio = snapshot.data!;
              final color = ratio > 0.9 ? Colors.red : (ratio > 0.7 ? Colors.orange : Colors.green);
              
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Row(
                    children: [
                      Icon(Icons.cloud, color: color, size: 20),
                      const SizedBox(width: 4),
                      FutureBuilder<double>(
                        future: _cloudService.getStorageUsageGB(),
                        builder: (context, usageSnapshot) {
                          if (!usageSnapshot.hasData) return const SizedBox();
                          
                          final usage = usageSnapshot.data!;
                          final limit = _cloudService.getStorageLimitGB();
                          
                          return Text(
                            '${usage.toStringAsFixed(1)}GB / ${limit.toInt()}GB',
                            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 업로드 진행률 표시
          _buildUploadProgressIndicator(),
          
          // 앨범 필터
          _buildAlbumFilter(),
          
          // 영상 목록
          Expanded(child: _buildVideoList()),
        ],
      ),
    );
  }

  /// 업그레이드 안내 화면
  Widget _buildUpgradeScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('클라우드 백업', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, color: Colors.white38, size: 100),
              const SizedBox(height: 24),
              const Text(
                '클라우드 백업',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Standard 등급 이상에서 사용 가능합니다.\n\n'
                '• Standard: 10GB 저장 공간\n'
                '• Premium: 50GB 저장 공간\n\n'
                '소중한 영상을 안전하게 보관하세요!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PaywallScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                ),
                child: const Text('업그레이드', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 업로드 진행률 표시
  Widget _buildUploadProgressIndicator() {
    return StreamBuilder<UploadProgress>(
      stream: _cloudService.uploadProgressStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        
        final progress = snapshot.data!;
        
        return Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white10,
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '업로드 중... ${progress.progressPercent}%',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progress.progressText,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 앨범 필터
  Widget _buildAlbumFilter() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Text('앨범:', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(width: 8),
          DropdownButton<String?>(
            value: _selectedAlbum,
            dropdownColor: Colors.grey[900],
            style: const TextStyle(color: Colors.white),
            underline: Container(height: 1, color: Colors.white24),
            items: [
              const DropdownMenuItem(value: null, child: Text('전체')),
              const DropdownMenuItem(value: 'Vlog', child: Text('Vlog')),
              const DropdownMenuItem(value: '여행', child: Text('여행')),
              const DropdownMenuItem(value: '맛집', child: Text('맛집')),
            ],
            onChanged: (value) {
              setState(() {
                _selectedAlbum = value;
              });
            },
          ),
          const Spacer(),
          // 즐겨찾기 필터는 추후 구현 가능
        ],
      ),
    );
  }

  /// 영상 목록
  Widget _buildVideoList() {
    return StreamBuilder<List<VideoMetadata>>(
      stream: _cloudService.getUserVideos(albumName: _selectedAlbum),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.amber));
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              '오류: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final videos = snapshot.data ?? [];

        if (videos.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_queue, color: Colors.white38, size: 80),
                const SizedBox(height: 16),
                Text(
                  _selectedAlbum == null 
                      ? '아직 백업된 영상이 없습니다.'
                      : '$_selectedAlbum 앨범에 영상이 없습니다.',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: videos.length,
          itemBuilder: (context, index) {
            final video = videos[index];
            return _buildVideoCard(video);
          },
        );
      },
    );
  }

  /// 영상 카드
  Widget _buildVideoCard(VideoMetadata video) {
    return Card(
      color: Colors.white10,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.videocam, color: Colors.white54),
        ),
        title: Text(
          video.fileName,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${video.albumName} • ${video.fileSizeText}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (video.uploadStatus != 'completed') ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    _getStatusText(video.uploadStatus),
                    style: TextStyle(
                      color: _getStatusColor(video.uploadStatus),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (video.uploadStatus == 'uploading') ...[
                    const SizedBox(width: 8),
                    Text(
                      '${video.uploadProgress}%',
                      style: const TextStyle(color: Colors.amber, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton(
          icon: const Icon(Icons.more_vert, color: Colors.white54),
          color: Colors.grey[900],
          itemBuilder: (context) => [
            PopupMenuItem(
              child: Row(
                children: [
                  Icon(
                    video.isFavorite ? Icons.star : Icons.star_border,
                    color: video.isFavorite ? Colors.amber : Colors.white54,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    video.isFavorite ? '즐겨찾기 해제' : '즐겨찾기',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              onTap: () {
                _cloudService.updateVideoMetadata(
                  videoId: video.videoId,
                  isFavorite: !video.isFavorite,
                );
              },
            ),
            const PopupMenuItem(
              child: Row(
                children: [
                  Icon(Icons.download, color: Colors.white54, size: 20),
                  SizedBox(width: 8),
                  Text('다운로드', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            PopupMenuItem(
              child: const Row(
                children: [
                  Icon(Icons.delete, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('삭제', style: TextStyle(color: Colors.red)),
                ],
              ),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('삭제 확인'),
                    content: const Text('이 영상을 클라우드에서 삭제하시겠습니까?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('취소'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('삭제'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await _cloudService.deleteVideo(video.videoId);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'queued':
        return '대기 중';
      case 'uploading':
        return '업로드 중';
      case 'completed':
        return '완료';
      case 'failed':
        return '실패';
      default:
        return '알 수 없음';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'queued':
        return Colors.orange;
      case 'uploading':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return Colors.white54;
    }
  }
}
