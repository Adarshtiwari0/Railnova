import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HomeSkin { signalBoard, metroCard, nightExpress }

/// Controls which of the 3 Home-screen visual skins is active.
/// Persisted so the choice survives an app restart.
class ThemeProvider extends ChangeNotifier {
  static const _prefsKey = "home_skin";

  HomeSkin _skin = HomeSkin.nightExpress;

  HomeSkin get skin => _skin;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);

    _skin = switch (saved) {
      "signalBoard" => HomeSkin.signalBoard,
      "metroCard" => HomeSkin.metroCard,
      "nightExpress" => HomeSkin.nightExpress,
      _ => HomeSkin.nightExpress,
    };

    notifyListeners();
  }

  Future<void> setSkin(HomeSkin skin) async {
    _skin = skin;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, skin.name);
  }
}
