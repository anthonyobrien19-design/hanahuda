// Remembers your online game on this device so a page reload (switching between
// desktop and phone view, or switching apps) can put you straight back in.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SavedSession {
  final String code, nick;
  final bool isHost, inGame;
  final int seat, n, target;
  const SavedSession({
    required this.code,
    required this.nick,
    required this.isHost,
    required this.seat,
    required this.n,
    required this.target,
    required this.inGame,
  });

  Map<String, Object> toJson() => {
        'code': code,
        'nick': nick,
        'isHost': isHost,
        'seat': seat,
        'n': n,
        'target': target,
        'inGame': inGame,
      };

  static SavedSession? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return SavedSession(
        code: '${j['code']}',
        nick: '${j['nick']}',
        isHost: j['isHost'] == true,
        seat: (j['seat'] as num).toInt(),
        n: (j['n'] as num).toInt(),
        target: (j['target'] as num).toInt(),
        inGame: j['inGame'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

class SessionStore {
  static const _key = 'hanahuda_session';
  static const _introKey = 'hanahuda_intro_seen';

  static Future<SavedSession?> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_key);
      return s == null ? null : SavedSession.fromJson(jsonDecode(s));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(SavedSession s) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(s.toJson()));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }

  static Future<bool> seenIntro() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_introKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> markIntroSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_introKey, true);
    } catch (_) {}
  }
}
