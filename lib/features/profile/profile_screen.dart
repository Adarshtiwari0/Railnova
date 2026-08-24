import 'package:flutter/material.dart';

import '../../core/navigation/smooth_route.dart';
import '../../screens/settings_screen.dart';

/// RailNova doesn't have user accounts — everything (favorites, recent
/// searches, theme) is stored on-device. This screen is just the app's
/// settings/info hub rather than a personal profile.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Profile"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.only(top: 30),
        children: [
          const Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  child: Icon(Icons.train, size: 40),
                ),
                SizedBox(height: 16),
                Text(
                  "RailNova",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  "Smart Railway Companion",
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text("Settings"),
            subtitle: const Text("Dark mode, notifications"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                SmoothRoute(page: const SettingsScreen()),
              );
            },
          ),

          const Divider(),
        ],
      ),
    );
  }
}
