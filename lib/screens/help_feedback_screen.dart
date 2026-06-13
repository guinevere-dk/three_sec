import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/moa_design_tokens.dart';

enum _SupportMode { help, feedback }

class HelpFeedbackScreen extends StatefulWidget {
  const HelpFeedbackScreen({super.key});

  @override
  State<HelpFeedbackScreen> createState() => _HelpFeedbackScreenState();
}

class _HelpFeedbackScreenState extends State<HelpFeedbackScreen> {
  _SupportMode _mode = _SupportMode.help;

  Future<void> _openFeedbackEmail() async {
    final supportEmail = Uri.parse(
      'mailto:dongkwon81@gmail.com?subject=MOA%20Support',
    );
    final ok = await launchUrl(supportEmail);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('메일 앱을 열 수 없습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MoaDesignTokens.background,
      appBar: AppBar(
        title: const Text('Help & Feedback'),
        backgroundColor: MoaDesignTokens.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _SupportModeCard(
            mode: _mode,
            onChanged: (mode) => setState(() => _mode = mode),
          ),
          const SizedBox(height: 16),
          if (_mode == _SupportMode.feedback)
            _FeedbackPanel(onOpenEmail: _openFeedbackEmail)
          else
            const _HelpGuidePanel(),
        ],
      ),
    );
  }
}

class _SupportModeCard extends StatelessWidget {
  const _SupportModeCard({required this.mode, required this.onChanged});

  final _SupportMode mode;
  final ValueChanged<_SupportMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SegmentedButton<_SupportMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: _SupportMode.help,
              icon: Icon(Icons.menu_book_outlined),
              label: Text('도움말'),
            ),
            ButtonSegment(
              value: _SupportMode.feedback,
              icon: Icon(Icons.rate_review_outlined),
              label: Text('개발자에게 피드백'),
            ),
          ],
          selected: {mode},
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return MoaDesignTokens.textPrimary;
              }
              return MoaDesignTokens.textMuted;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return MoaDesignTokens.accentSoft.withValues(alpha: 0.48);
              }
              return MoaDesignTokens.surfaceSolid;
            }),
            side: WidgetStateProperty.resolveWith((states) {
              return BorderSide(
                color: states.contains(WidgetState.selected)
                    ? MoaDesignTokens.accentStrong
                    : MoaDesignTokens.stroke,
              );
            }),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          onSelectionChanged: (selection) {
            final selected = selection.firstOrNull;
            if (selected != null) {
              onChanged(selected);
            }
          },
        ),
      ),
    );
  }
}

class _HelpGuidePanel extends StatelessWidget {
  const _HelpGuidePanel();

  static const List<_HelpSection> _sections = [
    _HelpSection(
      icon: Icons.videocam_outlined,
      title: '2초 촬영',
      bullets: [
        '촬영 화면의 REC 버튼을 누르면 짧은 2초 클립을 빠르게 기록합니다.',
        '같은 순간을 여러 번 남길 때는 앨범을 먼저 정한 뒤 이어서 촬영하면 정리가 쉽습니다.',
        '저장 중에는 앱을 바로 종료하지 말고 클립이 라이브러리에 나타나는지 확인해주세요.',
      ],
    ),
    _HelpSection(
      icon: Icons.photo_library_outlined,
      title: '라이브러리와 앨범',
      bullets: [
        '라이브러리에서는 촬영한 클립을 앨범별로 확인하고 선택할 수 있습니다.',
        '길게 누르면 여러 클립을 선택할 수 있고, 선택한 항목은 이동/삭제/복원 흐름에서 사용됩니다.',
        '휴지통으로 이동한 클립은 바로 원본 삭제가 아니라 복원 가능한 상태로 관리됩니다.',
      ],
    ),
    _HelpSection(
      icon: Icons.video_settings_outlined,
      title: 'Vlog 만들기와 편집',
      bullets: [
        '프로젝트 화면에서 사용할 클립을 고르면 하나의 Vlog 프로젝트로 이어 붙일 수 있습니다.',
        '편집 화면에서는 순서, 밝기, 색감, 오디오 정책을 확인한 뒤 내보내기를 진행합니다.',
        '내보내기 중에는 처리 상태가 끝날 때까지 기다리면 결과 영상이 저장됩니다.',
      ],
    ),
    _HelpSection(
      icon: Icons.cloud_outlined,
      title: '클라우드 백업',
      bullets: [
        'Standard 이상에서는 클립을 클라우드로 이동하거나 백업 상태를 확인할 수 있습니다.',
        '업로드 실패 시 네트워크 상태를 확인한 뒤 클라우드 백업 화면에서 다시 시도해주세요.',
        '구독이 만료되어도 기존 로컬 원본과 프로젝트는 유지됩니다.',
      ],
    ),
    _HelpSection(
      icon: Icons.account_circle_outlined,
      title: '계정과 구독',
      bullets: [
        '게스트 모드는 빠르게 앱을 둘러보기 위한 상태이며 클라우드 동기화 기능이 제한됩니다.',
        '로그인하면 프로필, 구독 상태, 클라우드 기능을 같은 계정 기준으로 확인할 수 있습니다.',
        '구독 관리는 프로필의 구독 항목에서 현재 플랜과 복원 흐름을 확인해주세요.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Text(
            'MOA 사용 도움말',
            style: TextStyle(
              color: MoaDesignTokens.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        for (final section in _sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _HelpSectionTile(section: section),
          ),
      ],
    );
  }
}

class _HelpSectionTile extends StatelessWidget {
  const _HelpSectionTile({required this.section});

  final _HelpSection section;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: MoaDesignTokens.accentSoft.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(MoaDesignTokens.radiusSm),
          ),
          child: Icon(section.icon, color: MoaDesignTokens.accentStrong),
        ),
        iconColor: MoaDesignTokens.textPrimary,
        collapsedIconColor: MoaDesignTokens.textFaint,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Text(
          section.title,
          style: const TextStyle(
            color: MoaDesignTokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        children: [
          for (final bullet in section.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: MoaDesignTokens.textFaint,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      bullet,
                      style: const TextStyle(
                        color: MoaDesignTokens.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.42,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  const _FeedbackPanel({required this.onOpenEmail});

  final VoidCallback onOpenEmail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.mark_email_read_outlined,
              color: MoaDesignTokens.accentStrong,
              size: 32,
            ),
            const SizedBox(height: 12),
            const Text(
              '개발자에게 피드백 보내기',
              style: TextStyle(
                color: MoaDesignTokens.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '문제가 생긴 화면, 어떤 작업 중이었는지, 기대한 결과를 함께 적어주시면 확인이 빠릅니다.',
              style: TextStyle(
                color: MoaDesignTokens.textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpenEmail,
                icon: const Icon(Icons.mail_outline),
                label: const Text('메일 앱 열기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpSection {
  const _HelpSection({
    required this.icon,
    required this.title,
    required this.bullets,
  });

  final IconData icon;
  final String title;
  final List<String> bullets;
}
