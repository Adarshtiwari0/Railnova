import 'package:flutter/material.dart';

import '../../providers/theme_provider.dart';

class _SkinOption {
  final HomeSkin skin;
  final String name;
  final String description;
  final List<Color> swatchColors;

  const _SkinOption({
    required this.skin,
    required this.name,
    required this.description,
    required this.swatchColors,
  });
}

const _options = [
  _SkinOption(
    skin: HomeSkin.signalBoard,
    name: "Signal Board",
    description: "Dark, departure-board style",
    swatchColors: [Color(0xff171029), Color(0xff8B5CF6)],
  ),
  _SkinOption(
    skin: HomeSkin.metroCard,
    name: "Metro Card",
    description: "Light, rounded, friendly",
    swatchColors: [Color(0xffF6F1FE), Color(0xff7C3AED)],
  ),
  _SkinOption(
    skin: HomeSkin.nightExpress,
    name: "Night Express",
    description: "Dark glass, neon purple",
    swatchColors: [Color(0xff0B0714), Color(0xffB18CFF)],
  ),
];

/// Opens the "App Theme" bottom sheet — same sheet from Settings and from
/// the gear icon on the Home screen itself.
void showThemePickerSheet(BuildContext context, ThemeProvider provider) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ThemeSheet(provider: provider),
  );
}

class _ThemeSheet extends StatelessWidget {
  final ThemeProvider provider;

  const _ThemeSheet({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
      decoration: const BoxDecoration(
        color: Color(0xff181820),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xff3A3A45),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const Text(
              "App Theme",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
            ),
            const SizedBox(height: 3),
            const Text(
              "Choose how Railnova looks",
              style: TextStyle(fontSize: 12.5, color: Color(0xff8A8A95)),
            ),
            const SizedBox(height: 18),
            for (final option in _options) ...[
              _SkinTile(
                option: option,
                selected: provider.skin == option.skin,
                onTap: () {
                  provider.setSkin(option.skin);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkinTile extends StatelessWidget {
  final _SkinOption option;
  final bool selected;
  final VoidCallback onTap;

  const _SkinTile({required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xffB18CFF);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected ? const Color(0xff241f33) : const Color(0xff1f1f28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? accent : Colors.transparent, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: option.swatchColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        option.description,
                        style: const TextStyle(fontSize: 12, color: Color(0xff8A8A95)),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? accent : Colors.transparent,
                    border: Border.all(color: selected ? accent : const Color(0xff4A4A56), width: 1.5),
                  ),
                  child: selected ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
