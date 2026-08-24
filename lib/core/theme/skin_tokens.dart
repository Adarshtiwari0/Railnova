import 'package:flutter/material.dart';

import '../../providers/theme_provider.dart';

/// The color/style palette for one of the 3 Home-screen skins — used by
/// every screen (not just Home) so the whole app matches the selected
/// theme, not just the Home screen.
class SkinTokens {
  final HomeSkin skin;
  final Color bg;
  final Color card;
  final Color primary;
  final Color primaryDeep;
  final Color accent; // secondary accent (amber/mint/cyan)
  final Color text;
  final Color dim;
  final Color border;
  final String? fontFamily;
  final Brightness brightness;

  const SkinTokens({
    required this.skin,
    required this.bg,
    required this.card,
    required this.primary,
    required this.primaryDeep,
    required this.accent,
    required this.text,
    required this.dim,
    required this.border,
    required this.fontFamily,
    required this.brightness,
  });

  static const signalBoard = SkinTokens(
    skin: HomeSkin.signalBoard,
    bg: Color(0xff171029),
    card: Color(0xff1F1638),
    primary: Color(0xff8B5CF6),
    primaryDeep: Color(0xff6D28D9),
    accent: Color(0xffF0A83C),
    text: Color(0xffF0ECFA),
    dim: Color(0xff9B8FBD),
    border: Color(0x2E8B5CF6),
    fontFamily: "monospace",
    brightness: Brightness.dark,
  );

  static const metroCard = SkinTokens(
    skin: HomeSkin.metroCard,
    bg: Color(0xffF6F1FE),
    card: Colors.white,
    primary: Color(0xff7C3AED),
    primaryDeep: Color(0xff4C1D95),
    accent: Color(0xff12B886),
    text: Color(0xff2A1B4D),
    dim: Color(0xff8577A8),
    border: Color(0x1F7C3AED),
    fontFamily: null,
    brightness: Brightness.light,
  );

  static const nightExpress = SkinTokens(
    skin: HomeSkin.nightExpress,
    bg: Color(0xff0B0714),
    card: Color(0x15A855F7),
    primary: Color(0xffB18CFF),
    primaryDeep: Color(0xff7C3AED),
    accent: Color(0xff4FE3D0),
    text: Color(0xffEDE7FA),
    dim: Color(0xff6E6390),
    border: Color(0x40A855F7),
    fontFamily: null,
    brightness: Brightness.dark,
  );

  static SkinTokens of(HomeSkin skin) {
    return switch (skin) {
      HomeSkin.signalBoard => signalBoard,
      HomeSkin.metroCard => metroCard,
      HomeSkin.nightExpress => nightExpress,
    };
  }

  /// A ready-to-use AppBar for this skin, so every screen's top bar
  /// automatically matches without repeating this styling everywhere.
  AppBar appBar(String title, {List<Widget>? actions}) {
    return AppBar(
      title: Text(title, style: TextStyle(fontFamily: fontFamily, color: text)),
      backgroundColor: card,
      elevation: 0,
      iconTheme: IconThemeData(color: text),
      actions: actions,
    );
  }

  BoxDecoration cardDecoration({double radius = 18}) {
    return BoxDecoration(
      color: card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
    );
  }

  ButtonStyle get primaryButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: primary,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 16),
    textStyle: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.bold),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}
