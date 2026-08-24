import 'package:shared_preferences/shared_preferences.dart';

class RecentSearchService {
  // NOTE: this used to be "recent_searches", which collided with the key
  // live_train_screen.dart uses for recent *train number* lookups (stored
  // as a JSON string instead of a String list). Reading one as the other's
  // type throws, which is why main.dart was force-clearing this key on
  // every app launch. Renamed to keep the two histories independent.
  static const String recentKey = "recent_route_searches";

  Future<List<String>> getRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(recentKey) ?? [];
  }

  Future<void> saveSearch(String route) async {
    final prefs = await SharedPreferences.getInstance();

    List<String> searches = prefs.getStringList(recentKey) ?? [];

    searches.remove(route); // Duplicate हटाओ

    searches.insert(0, route); // सबसे ऊपर नई Search

    if (searches.length > 10) {
      searches = searches.sublist(0, 10);
    }

    await prefs.setStringList(recentKey, searches);
  }

  Future<void> clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(recentKey);
  }
}
