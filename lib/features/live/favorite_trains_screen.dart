import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/skin_tokens.dart';
import '../../providers/theme_provider.dart';
import 'live_train_screen.dart';

/// Simple list of trains the user starred from LiveTrainScreen — tap one
/// to jump straight into tracking it.
class FavoriteTrainsScreen extends StatefulWidget {
  const FavoriteTrainsScreen({super.key});

  @override
  State<FavoriteTrainsScreen> createState() => _FavoriteTrainsScreenState();
}

class _FavoriteTrainsScreenState extends State<FavoriteTrainsScreen> {
  List<Map<String, String>> favorites = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("favorite_trains");
    if (raw != null) {
      final decoded = jsonDecode(raw) as List;
      favorites = decoded.map((e) => Map<String, String>.from(e)).toList();
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return Scaffold(
      backgroundColor: skin.bg,
      appBar: AppBar(
        backgroundColor: skin.primary,
        title: const Text("Favorite Trains", style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : favorites.isEmpty
              ? Center(
                  child: Text(
                    "No favorite trains yet.\nTap the star while tracking a train to save it.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: skin.dim),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: favorites.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final t = favorites[index];
                    return Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveTrainScreen(initialTrainNumber: t["number"]),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: skin.cardDecoration(radius: 14),
                          child: Row(
                            children: [
                              Icon(Icons.star_rounded, color: skin.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t["number"] ?? "",
                                      style: TextStyle(fontWeight: FontWeight.bold, color: skin.text),
                                    ),
                                    Text(
                                      t["name"] ?? "",
                                      style: TextStyle(fontSize: 12.5, color: skin.dim),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: skin.dim),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
