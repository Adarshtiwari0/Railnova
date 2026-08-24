import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../core/widgets/theme_picker_sheet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _skinLabel(HomeSkin skin) {
    return switch (skin) {
      HomeSkin.signalBoard => "Signal Board",
      HomeSkin.metroCard => "Metro Card",
      HomeSkin.nightExpress => "Night Express",
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: const Color(0xff1565C0),
      ),
      body: ListView(
        children: [
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: const Text("App Theme"),
                subtitle: Text(_skinLabel(themeProvider.skin)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showThemePickerSheet(context, themeProvider),
              );
            },
          ),
          const Divider(),

          const ListTile(
            leading: Icon(Icons.notifications),
            title: Text("Notifications"),
            subtitle: Text("Delay alerts turn on when you favorite a train"),
          ),
          const Divider(),

          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text("About RailNova"),
            subtitle: Text("Version 1.0.0"),
          ),
        ],
      ),
    );
  }
}
