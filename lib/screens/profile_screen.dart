import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../managers/user_status_manager.dart';
import '../managers/video_manager.dart';
import 'paywall_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final UserStatusManager _userStatusManager = UserStatusManager();
  String _storageUsage = "Calculated...";

  @override
  void initState() {
    super.initState();
    _updateStorageUsage();
  }

  Future<void> _updateStorageUsage() async {
    final videoManager = Provider.of<VideoManager>(context, listen: false);
    final usage = await videoManager.calculateStorageUsage();
    if (mounted) {
      setState(() {
        _storageUsage = usage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final isPremium = _userStatusManager.currentTier == UserTier.premium;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text("Profile", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.share, color: Colors.black)),
          IconButton(
             onPressed: () => _authService.signOut(), 
             icon: const Icon(Icons.logout, color: Colors.red)
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            
            // 1. Profile Header
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                    image: const DecorationImage(
                      image: AssetImage('assets/profile_placeholder.png'), // Placeholder
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: const Icon(Icons.person, size: 50, color: Colors.grey),
                ),
                if (isPremium)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFD700),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black26)],
                    ),
                    child: const Icon(Icons.star, color: Colors.white, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              user?.email ?? "Guest User",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (!isPremium)
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen())),
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text("UPGRADE TO PRO", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),

            const SizedBox(height: 32),

            // 2. Stats Row
            Consumer<VideoManager>(
              builder: (context, videoManager, child) {
                final clipCount = NumberFormat.decimalPattern().format(videoManager.totalClipCount);
                final vlogCount = NumberFormat.decimalPattern().format(videoManager.totalVlogCount);
                
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem(clipCount, "Clips"),
                    Container(width: 1, height: 40, color: Colors.grey[300]),
                    _buildStatItem(vlogCount, "Vlogs"),
                    Container(width: 1, height: 40, color: Colors.grey[300]),
                    _buildStatItem(_storageUsage, "Used"),
                  ],
                );
              },
            ),
            
            const SizedBox(height: 32),
            const Divider(height: 1),
            
            // 3. Menu List
            _buildMenuItem(Icons.cloud_upload_outlined, "Cloud Sync", trailing: Switch(value: false, onChanged: (v){})),
            _buildMenuItem(Icons.delete_outline, "Trash"),
            _buildMenuItem(Icons.settings_outlined, "Settings"),
            _buildMenuItem(Icons.help_outline, "Help & Support"),
            
            const SizedBox(height: 40),
            
            const Text(
              "v1.0.0 (Build 12)",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _buildMenuItem(IconData icon, String title, {Widget? trailing}) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {}, // Connector placeholder
    );
  }
}
