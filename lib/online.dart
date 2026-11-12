// Online play data layer (no UI). Uses the Firebase Realtime Database REST API,
// so no Firebase plugins or config files are needed - only the `http` package.
//
// SETUP (once): create a Firebase project, add a Realtime Database, set its rules to
//   { "rules": { ".read": true, ".write": true } }
// then paste the database URL below, e.g. https://my-game-default-rtdb.firebaseio.com
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'hanahuda_engine.dart';

const String kDatabaseUrl = 'https://hanahuda-419b7-default-rtdb.firebaseio.com';

/// Address of your website (used to build invite links).
const String kSiteUrl = 'https://anthonyobrien19-design.github.io/hanahuda/';

String inviteLink(String code) => '$kSiteUrl?join=$code';


/// Optional relay (TURN) server so voice also works for players on mobile data or strict networks.
/// Leave empty to use only the free Google STUN server. Example for a Metered account:
///   kTurnUrl = 'turn:global.relay.metered.ca:80', plus your username and password.
const String kTurnUrl = 'turn:global.relay.metered.ca:80';
const String kTurnUser = '018617eeae041b12a14f7994';
const String kTurnPass = 'UYHKjP42T6QN5xT0';

class Rtdb {
  static bool get configured => kDatabaseUrl.trim().isNotEmpty;

  // A request that hangs (for example while the tab is in the background) must not freeze the game.
  static const _wait = Duration(seconds: 8);

  static String get _base {
    final u = kDatabaseUrl.trim();
    return u.endsWith('/') ? u.substring(0, u.length - 1) : u;
  }

  static Uri _u(String path) => Uri.parse('$_base/$path.json');

  static Future<dynamic> get(String path) async {
    final r = await http.get(_u(path)).timeout(_wait);
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    return jsonDecode(r.body);
  }

  static Future<void> put(String path, Object? data) async {
    final r = await http.put(_u(path), body: jsonEncode(data)).timeout(_wait);
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  }

  static Future<void> patch(String path, Map<String, Object?> data) async {
    final r = await http.patch(_u(path), body: jsonEncode(data)).timeout(_wait);
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  }

  static Future<void> delete(String path) async {
    await http.delete(_u(path)).timeout(_wait);
  }
}

/// Four-letter room code (no confusing letters).
String newRoomCode() {
  const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  final r = Random();
  return String.fromCharCodes([for (var i = 0; i < 4; i++) letters.codeUnitAt(r.nextInt(letters.length))]);
}

/// Realtime Database drops empty lists and may return lists as maps.
List<int> asIds(dynamic v) {
  if (v == null) return [];
  final it = v is Map ? v.values : (v as Iterable);
  return [for (final x in it) if (x is num) x.toInt()];
}

HCard cardFromId(int id) => HCard(id ~/ 4, id % 4);

/// Settings that tell a GameScreen it is part of an online game.
class OnlineConfig {
  final String code;
  final bool isHost;
  final int mySeat;
  final List<String?> seatNicks; // index = seat, null = CPU
  const OnlineConfig({required this.code, required this.isHost, required this.mySeat, required this.seatNicks});
}

/// Realtime Database returns dense integer-keyed maps as lists; turn either into a list.
List<dynamic> asList(dynamic v) {
  if (v == null) return [];
  if (v is List) return v;
  if (v is Map) {
    final ks = v.keys.map((k) => int.tryParse('$k') ?? 0).toList()..sort();
    return [for (final k in ks) v['$k']];
  }
  return [];
}

/// Same idea for maps keyed by small numbers (seats, teams): always a String-keyed map.
Map<String, dynamic> keyed(dynamic v) {
  if (v == null) return {};
  if (v is Map) return {for (final e in v.entries) '${e.key}': e.value};
  if (v is List) return {for (var i = 0; i < v.length; i++) if (v[i] != null) '$i': v[i]};
  return {};
}
