import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/moa_design_tokens.dart';

class BGMTrack {
  final String title;
  final String author;
  final String path;
  final String category;

  BGMTrack({
    required this.title,
    required this.author,
    required this.path,
    required this.category,
  });
}

class BGMPickerScreen extends StatefulWidget {
  const BGMPickerScreen({super.key});

  @override
  State<BGMPickerScreen> createState() => _BGMPickerScreenState();
}

class _BGMPickerScreenState extends State<BGMPickerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  VideoPlayerController? _previewController;
  BGMTrack? _selectedTrack;
  double _volume = 0.5;

  final List<String> _categories = ['감성적인', '신나는', '잔잔한', '세련된'];

  // 더미 데이터: 실제 앱에서는 서버에서 불러오거나 로컬 자산을 사용합니다.
  final List<BGMTrack> _allTracks = [
    BGMTrack(
      title: 'Sunset Walk',
      author: 'Lo-fi Artist',
      path: 'https://www.sample-videos.com/audio/mp3/wave.mp3',
      category: '감성적인',
    ),
    BGMTrack(
      title: 'Morning Coffee',
      author: 'Acoustic Soul',
      path: 'https://www.sample-videos.com/audio/mp3/crowd-cheering.mp3',
      category: '감성적인',
    ),
    BGMTrack(
      title: 'Urban Beat',
      author: 'DJ City',
      path: 'https://www.sample-videos.com/audio/mp3/wave.mp3',
      category: '신나는',
    ),
    BGMTrack(
      title: 'Summer Dance',
      author: 'Pop Maker',
      path: 'https://www.sample-videos.com/audio/mp3/crowd-cheering.mp3',
      category: '신나는',
    ),
    BGMTrack(
      title: 'Deep Sleep',
      author: 'Ambient King',
      path: 'https://www.sample-videos.com/audio/mp3/wave.mp3',
      category: '잔잔한',
    ),
    BGMTrack(
      title: 'Rainy Night',
      author: 'Piano Man',
      path: 'https://www.sample-videos.com/audio/mp3/crowd-cheering.mp3',
      category: '잔잔한',
    ),
    BGMTrack(
      title: 'Fashion Show',
      author: 'Electro Chic',
      path: 'https://www.sample-videos.com/audio/mp3/wave.mp3',
      category: '세련된',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _playPreview(BGMTrack track) async {
    if (_previewController != null) {
      await _previewController!.dispose();
    }

    setState(() {
      _selectedTrack = track;
    });

    // Note: In a real app, you would use local assets or valid remote URLs.
    // Using networkUrl for demo purposes.
    _previewController = VideoPlayerController.networkUrl(Uri.parse(track.path))
      ..initialize().then((_) {
        _previewController!.setVolume(_volume);
        _previewController!.play();
        _previewController!.setLooping(true);
        setState(() {});
      });
  }

  void _onConfirm() {
    if (_selectedTrack != null) {
      Navigator.pop(context, {
        'bgmPath': _selectedTrack!.path,
        'volume': _volume,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MoaDesignTokens.background,
      appBar: AppBar(
        backgroundColor: MoaDesignTokens.background,
        iconTheme: const IconThemeData(color: MoaDesignTokens.textPrimary),
        title: const Text(
          '배경음악 선택',
          style: TextStyle(
            color: MoaDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _selectedTrack != null ? _onConfirm : null,
            child: Text(
              '선택 완료',
              style: TextStyle(
                color: _selectedTrack != null
                    ? MoaDesignTokens.accentStrong
                    : MoaDesignTokens.textFaint,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: MoaDesignTokens.accentStrong,
          labelColor: MoaDesignTokens.textPrimary,
          unselectedLabelColor: MoaDesignTokens.textMuted,
          tabs: _categories.map((cat) => Tab(text: cat)).toList(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _categories.map((cat) => _buildTrackList(cat)).toList(),
            ),
          ),
          if (_selectedTrack != null) _buildPreviewPlayer(),
        ],
      ),
    );
  }

  Widget _buildTrackList(String category) {
    final tracks = _allTracks.where((t) => t.category == category).toList();
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isSelected = _selectedTrack == track;
        return ListTile(
          onTap: () => _playPreview(track),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isSelected
                  ? MoaDesignTokens.accentSoft.withValues(alpha: 0.55)
                  : MoaDesignTokens.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? MoaDesignTokens.accent.withValues(alpha: 0.58)
                    : MoaDesignTokens.stroke,
              ),
            ),
            child: Icon(
              isSelected ? Icons.music_note : Icons.music_note_outlined,
              color: isSelected
                  ? MoaDesignTokens.accentStrong
                  : MoaDesignTokens.textMuted,
            ),
          ),
          title: Text(
            track.title,
            style: TextStyle(
              color: isSelected
                  ? MoaDesignTokens.textPrimary
                  : MoaDesignTokens.textMuted,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            track.author,
            style: const TextStyle(
              color: MoaDesignTokens.textFaint,
              fontSize: 12,
            ),
          ),
          trailing:
              isSelected &&
                  _previewController != null &&
                  _previewController!.value.isPlaying
              ? const Icon(Icons.volume_up, color: MoaDesignTokens.accentStrong)
              : const Icon(Icons.play_arrow, color: MoaDesignTokens.textFaint),
        );
      },
    );
  }

  Widget _buildPreviewPlayer() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MoaDesignTokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: MoaDesignTokens.stroke),
        boxShadow: MoaDesignTokens.panelShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.volume_down,
                color: MoaDesignTokens.textMuted,
                size: 20,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: MoaDesignTokens.accentStrong,
                    inactiveTrackColor: MoaDesignTokens.stroke,
                    thumbColor: MoaDesignTokens.accentStrong,
                    overlayColor: MoaDesignTokens.accent.withValues(
                      alpha: 0.16,
                    ),
                    trackHeight: 2,
                  ),
                  child: Slider(
                    value: _volume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (value) {
                      setState(() {
                        _volume = value;
                        _previewController?.setVolume(_volume);
                      });
                    },
                  ),
                ),
              ),
              const Icon(
                Icons.volume_up,
                color: MoaDesignTokens.textMuted,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '선택됨: ${_selectedTrack?.title} - 볼륨: ${(_volume * 100).toInt()}%',
            style: const TextStyle(
              color: MoaDesignTokens.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
