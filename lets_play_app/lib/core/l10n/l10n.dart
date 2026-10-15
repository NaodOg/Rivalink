import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight localization: a language code + a string table.
/// Rebuilds the app when the language changes (see main.dart).
class L10n {
  L10n._();

  static final ValueNotifier<String> locale = ValueNotifier('en');

  static const Map<String, String> languageNames = {
    'en': 'English',
    'am': 'አማርኛ',
  };

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      locale.value = prefs.getString('language') ?? 'en';
    } catch (_) {
      locale.value = 'en';
    }
  }

  static Future<void> setLanguage(String code) async {
    locale.value = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', code);
    } catch (_) {}
  }

  /// Translate [key]; falls back to English, then the key itself.
  static String t(String key) {
    final table = _strings[locale.value] ?? _strings['en']!;
    return table[key] ?? _strings['en']![key] ?? key;
  }

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      'nav.home': 'Home',
      'nav.explore': 'Explore',
      'nav.host': 'Host',
      'nav.leagues': 'Leagues',
      'nav.profile': 'Profile',
      'home.morning': 'Good morning',
      'home.afternoon': 'Good afternoon',
      'home.evening': 'Good evening',
      'home.ready': 'Ready to play today?',
      'home.search': 'Search matches, venues, players…',
      'home.for_you': 'For you',
      'home.recommended': 'Recommended',
      'home.your_matches': 'Your matches',
      'home.venues': 'Venues nearby',
      'home.leagues': 'Active leagues',
      'home.pickup': 'Pickup & ranked',
      'home.book_hour': 'Book by the hour',
      'home.compete': 'Compete',
      'common.view_all': 'View all',
      'common.book': 'Book',
      'common.see_all': 'See all',
      'common.retry': 'Retry',
      'common.language': 'Language',
    },
    'am': {
      'nav.home': 'መነሻ',
      'nav.explore': 'ያስሱ',
      'nav.host': 'አዘጋጅ',
      'nav.leagues': 'ሊጎች',
      'nav.profile': 'መገለጫ',
      'home.morning': 'እንደምን አደሩ',
      'home.afternoon': 'እንደምን ዋሉ',
      'home.evening': 'እንደምን አመሹ',
      'home.ready': 'ዛሬ ለመጫወት ተዘጋጅተዋል?',
      'home.search': 'ግጥሚያዎች፣ ሜዳዎች፣ ተጫዋቾች ይፈልጉ…',
      'home.for_you': 'ለእርስዎ',
      'home.recommended': 'የሚመከሩ',
      'home.your_matches': 'ግጥሚያዎችዎ',
      'home.venues': 'አቅራቢያ ያሉ ሜዳዎች',
      'home.leagues': 'ንቁ ሊጎች',
      'home.pickup': 'ፈጣን እና ደረጃ',
      'home.book_hour': 'በሰዓት ያስይዙ',
      'home.compete': 'ይወዳደሩ',
      'common.view_all': 'ሁሉንም ይመልከቱ',
      'common.book': 'ያስይዙ',
      'common.see_all': 'ሁሉንም',
      'common.retry': 'እንደገና ይሞክሩ',
      'common.language': 'ቋንቋ',
    },
  };
}
