import 'package:flutter/material.dart';
import 'dart:io';
import '../services/auth_service.dart';

/// 소셜 로그인 화면
/// 
/// 지원 플랫폼:
/// - Google (Android/iOS 모두)
/// - Apple (iOS만)
/// - Kakao (Android/iOS)
/// - Naver (출시 이후 토큰 발급 전까지 숨김)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black, Colors.grey[900]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 로고 및 타이틀
                  const Icon(
                    Icons.videocam_rounded,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '3s',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '3초의 일상을 기록하세요',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[400],
                    ),
                  ),
                  
                  const SizedBox(height: 80),
                  
                  // 로딩 인디케이터 또는 로그인 버튼들
                  if (_isLoading)
                    const CircularProgressIndicator(color: Colors.white)
                  else
                    Column(
                      children: [
                        // Google 로그인 버튼
                        _buildSocialButton(
                          onPressed: _handleGoogleSignIn,
                          backgroundColor: Colors.white,
                          textColor: Colors.black87,
                          leading: _buildProviderBadge(
                            label: 'G',
                            backgroundColor: Colors.white,
                            textColor: const Color(0xFF4285F4),
                            borderColor: const Color(0xFFE5E7EB),
                          ),
                          label: 'Continue with Google',
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Apple 로그인 버튼 (iOS만)
                        if (Platform.isIOS)
                          _buildSocialButton(
                            onPressed: _handleAppleSignIn,
                            backgroundColor: Colors.black,
                            textColor: Colors.white,
                            leading: _buildProviderBadge(
                              label: '',
                              backgroundColor: Colors.white,
                              textColor: Colors.black,
                            ),
                            label: 'Continue with Apple',
                            borderColor: Colors.white,
                          ),
                        
                        if (Platform.isIOS) const SizedBox(height: 16),
                        
                        // Kakao 로그인
                        _buildSocialButton(
                          onPressed: _handleKakaoSignIn,
                          backgroundColor: const Color(0xFFFEE500),
                          textColor: Colors.black87,
                          leading: _buildProviderBadge(
                            label: 'K',
                            backgroundColor: const Color(0xFF381E1F),
                            textColor: const Color(0xFFFEE500),
                          ),
                          label: 'Continue with Kakao',
                        ),
                      ],
                    ),
                  
                  const SizedBox(height: 60),
                  
                  // 약관 동의 문구
                  Text(
                    'By continuing, you agree to our\nTerms of Service and Privacy Policy',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 소셜 로그인 버튼 빌더
  Widget _buildSocialButton({
    required VoidCallback onPressed,
    required Color backgroundColor,
    required Color textColor,
    Widget? leading,
    IconData? icon,
    required String label,
    Color? borderColor,
    bool isDisabled = false,
  }) {
    return ElevatedButton(
      onPressed: isDisabled ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: textColor,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: borderColor != null 
            ? BorderSide(color: borderColor, width: 1)
            : BorderSide.none,
        ),
        elevation: isDisabled ? 0 : 2,
        disabledBackgroundColor: Colors.grey[800],
        disabledForegroundColor: Colors.grey[600],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          leading ?? Icon(icon ?? Icons.login, size: 24),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderBadge({
    required String label,
    required Color backgroundColor,
    required Color textColor,
    Color? borderColor,
  }) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: borderColor != null
            ? Border.all(color: borderColor, width: 1)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }

  /// Google 로그인 처리
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final userCredential = await _authService.signInWithGoogle();
      if (userCredential != null && mounted) {
        // 로그인 성공 시 AuthGate가 자동으로 메인 화면으로 이동
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Welcome to 3s!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Apple 로그인 처리
  Future<void> _handleAppleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final userCredential = await _authService.signInWithApple();
      if (userCredential != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Welcome to 3s!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Kakao 로그인 처리 (추후 구현)
  Future<void> _handleKakaoSignIn() async {
    setState(() => _isLoading = true);
    try {
      final userCredential = await _authService.signInWithKakao();
      if (userCredential != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Welcome to 3s!')),
        );
      }
    } on AuthServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.userMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Naver 로그인 처리 (추후 구현)
  Future<void> _handleNaverSignIn() async {
    setState(() => _isLoading = true);
    try {
      final userCredential = await _authService.signInWithNaver();
      if (userCredential != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Welcome to 3s!')),
        );
      }
    } on AuthServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.userMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
