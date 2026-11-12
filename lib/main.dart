// Palauan Hanahuda - Flutter UI.
// Files needed in lib/: main.dart, hanahuda_engine.dart, hanahuda_ai.dart
// Card art (optional): assets/cards/<set>_<index>.png, e.g. 0_0.png ... 11_3.png.
// Without art, cards draw as colored placeholders.
import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'hanahuda_engine.dart';
import 'hanahuda_ai.dart';
import 'online.dart';
import 'session.dart';
import 'voice.dart';

void main() => runApp(const HanahudaApp());

class HanahudaApp extends StatelessWidget {
  const HanahudaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Hanahuda',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E20), brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: const SetupScreen(),
      );
}


// ---------------------------------------------------------------- Audio
// Optional files (the game stays silent if a file is missing):
//   assets/music/theme.mp3          looping background music
//   assets/sfx/deal.mp3, capture.mp3, flip.mp3, yak.mp3
/// Background music files in assets/music/. One file loops; several play one after another.
const List<String> kMusicTracks = ['theme.mp3'];

class AudioManager {
  AudioManager._();
  static final AudioManager instance = AudioManager._();
  final AudioPlayer _music = AudioPlayer();
  final AudioPlayer _sfx = AudioPlayer();
  bool musicOn = true;
  bool sfxOn = true;
  bool _started = false;
  String musicStatus = 'not started';
  String sfxStatus = 'not played yet';

  int _trackIdx = 0;
  StreamSubscription<void>? _sub;

  Future<void> _playTrack() async {
    final name = kMusicTracks[_trackIdx % kMusicTracks.length];
    await _music.play(AssetSource('music/$name'));
    musicStatus = 'playing assets/music/$name';
  }

  Future<void> startMusic() async {
    if (!musicOn) return;
    try {
      await _music.setVolume(0.4);
      final many = kMusicTracks.length > 1;
      await _music.setReleaseMode(many ? ReleaseMode.release : ReleaseMode.loop);
      _sub ??= _music.onPlayerComplete.listen((_) {
        if (many && _started) {
          _trackIdx = (_trackIdx + 1) % kMusicTracks.length;
          _playTrack();
        }
      });
      await _playTrack();
      _started = true;
    } catch (e) {
      musicStatus = 'cannot play music: $e';
    }
  }

  Future<void> stopMusic() async {
    try {
      await _music.stop();
      _started = false;
    } catch (_) {}
  }

  Future<void> setMusic(bool on) async {
    musicOn = on;
    if (on) {
      if (!_started) await startMusic();
    } else {
      await stopMusic();
    }
  }

  Future<void> sfx(String name) async {
    if (!sfxOn) return;
    try {
      await _sfx.stop();
      await _sfx.play(AssetSource('sfx/$name.mp3'));
      sfxStatus = 'played sfx/$name.mp3';
    } catch (e) {
      sfxStatus = 'cannot play sfx/$name.mp3: $e';
    }
  }
}

// ---------------------------------------------------------------- Table background
class FeltPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = Colors.white.withOpacity(0.045)
      ..strokeWidth = 1;
    for (double x = -s.height; x < s.width; x += 30) {
      c.drawLine(Offset(x, 0), Offset(x + s.height, s.height), p);
      c.drawLine(Offset(x + s.height, 0), Offset(x, s.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Set to true to use assets/backgrounds/table.jpg instead of the green felt.
const bool kUseImageBackground = false;

Widget _felt() => Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(0, -0.2), radius: 1.1, colors: [Color(0xFF2E7D4F), Color(0xFF14412A), Color(0xFF0A2417)]),
      ),
      child: CustomPaint(painter: FeltPainter()),
    );

Widget gameBackground() => !kUseImageBackground ? _felt() : Stack(fit: StackFit.expand, children: [
      Image.asset(
        'assets/backgrounds/table.jpg',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/backgrounds/table.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(center: Alignment(0, -0.2), radius: 1.1, colors: [Color(0xFF2E7D4F), Color(0xFF14412A), Color(0xFF0A2417)]),
            ),
            child: CustomPaint(painter: FeltPainter()),
          ),
        ),
      ),
      // Dark overlay keeps cards readable over any picture you add.
      Container(color: Colors.black.withOpacity(0.2)),
    ]);

// ---------------------------------------------------------------- Setup
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

String _lastNick = '';

class _SetupScreenState extends State<SetupScreen> {
  int players = 2;
  int target = 5000;
  bool listPublicly = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  /// On launch: rejoin a game this device was in, follow an invite link, or show the intro once.
  Future<void> _startup() async {
    final link = Uri.base.queryParameters['join']?.toUpperCase();
    final saved = await SessionStore.load();
    if (saved != null && Rtdb.configured && (link == null || link == saved.code)) {
      if (await _resume(saved)) return;
    } else if (saved != null) {
      await SessionStore.clear();
    }
    if (link != null && link.length == 4 && Rtdb.configured) {
      await _join(preCode: link);
      return;
    }
    if (!await SessionStore.seenIntro() && mounted) {
      await SessionStore.markIntroSeen();
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const IntroScreen()));
    }
  }

  Future<bool> _resume(SavedSession s) async {
    try {
      final lobby = await Rtdb.get('rooms/${s.code}/lobby');
      if (lobby is! Map) {
        await SessionStore.clear();
        return false;
      }
      final seats = keyed(lobby['seats']);
      final nicks = List<String?>.generate(s.n, (i) => seats['$i']?.toString());
      final started = lobby['started'] == true || s.inGame;
      if (!mounted) return false;
      _msg('Rejoining game ${s.code}...');
      if (!started) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => LobbyScreen(nick: s.nick, code: s.code, isHost: s.isHost, mySeat: s.seat, n: s.n, target: s.target)));
        return true;
      }
      Map<String, dynamic>? cp;
      if (s.isHost) {
        final c = await Rtdb.get('rooms/${s.code}/checkpoint');
        if (c is Map) cp = Map<String, dynamic>.from(c);
        if (cp == null) {
          await SessionStore.clear();
          return false;
        }
      }
      if (!mounted) return false;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GameScreen(
            playerCount: s.n,
            target: s.target,
            online: OnlineConfig(code: s.code, isHost: s.isHost, mySeat: s.seat, seatNicks: nicks),
            resume: cp,
          ),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _askText(String title, String hint, {int max = 12, bool upper = false, String initial = ''}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: max,
          textCapitalization: upper ? TextCapitalization.characters : TextCapitalization.words,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
        ],
      ),
    );
  }

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _host() async {
    if (!Rtdb.configured) {
      _msg('Online play is not set up yet. Add your database URL in online.dart.');
      return;
    }
    final nick = await _askText('Pick a nickname', 'Nickname', initial: _lastNick);
    if (nick == null || nick.isEmpty) return;
    _lastNick = nick;
    try {
      String code;
      do {
        code = newRoomCode();
      } while (await Rtdb.get('rooms/$code') != null);
      await Rtdb.put('rooms/$code', {
        'lobby': {'host': nick, 'n': players, 'target': target, 'started': false, 'seats': {'0': nick}},
      });
      if (listPublicly) {
        await Rtdb.put('openGames/$code', {'host': nick, 'n': players, 'target': target, 't': DateTime.now().millisecondsSinceEpoch});
      }
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => LobbyScreen(nick: nick, code: code, isHost: true, mySeat: 0, n: players, target: target)));
    } catch (e) {
      _msg('Could not create the game: $e');
    }
  }

  /// Join by typing a code (or from an invite link, which fills the code in).
  Future<void> _join({String? preCode}) async {
    if (!Rtdb.configured) {
      _msg('Online play is not set up yet. Add your database URL in online.dart.');
      return;
    }
    final nick = await _askText('Pick a nickname', 'Nickname', initial: _lastNick);
    if (nick == null || nick.isEmpty) return;
    _lastNick = nick;
    final code = preCode ?? await _askText('Enter the game code', 'ABCD', max: 4, upper: true);
    if (code == null || code.length != 4) return;
    await _joinCode(code.toUpperCase(), nick);
  }

  Future<void> _browse() async {
    if (!Rtdb.configured) {
      _msg('Online play is not set up yet. Add your database URL in online.dart.');
      return;
    }
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const BrowseGamesScreen()));
    if (code == null || !mounted) return;
    final nick = await _askText('Pick a nickname', 'Nickname', initial: _lastNick);
    if (nick == null || nick.isEmpty) return;
    _lastNick = nick;
    await _joinCode(code, nick);
  }

  Future<void> _joinCode(String code, String nick) async {
    try {
      final lobby = await Rtdb.get('rooms/$code/lobby');
      if (lobby is! Map) {
        _msg('No game found with that code.');
        return;
      }
      if (lobby['started'] == true) {
        _msg('That game has already started.');
        return;
      }
      final n = (lobby['n'] as num).toInt();
      final tgt = (lobby['target'] as num).toInt();
      final seats = keyed(lobby['seats']);
      var seat = -1;
      for (var i = 1; i < n; i++) {
        if (seats['$i'] == null) {
          seat = i;
          break;
        }
      }
      if (seat < 0) {
        _msg('That game is full.');
        return;
      }
      await Rtdb.put('rooms/$code/lobby/seats/$seat', nick);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => LobbyScreen(nick: nick, code: code, isHost: false, mySeat: seat, n: n, target: tgt)));
    } catch (e) {
      _msg('Could not join: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF14412A),
        body: SafeArea(
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Hanahuda', textAlign: TextAlign.center, style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Me dou kat!', textAlign: TextAlign.center, style: TextStyle(fontSize: 22)),
                const SizedBox(height: 40),
                const Text('Players'),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 2, label: Text('2')),
                    ButtonSegment(value: 3, label: Text('3')),
                    ButtonSegment(value: 4, label: Text('4 (teams)')),
                  ],
                  selected: {players},
                  onSelectionChanged: (s) => setState(() => players = s.first),
                ),
                const SizedBox(height: 24),
                const Text('Play to'),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 2000, label: Text('2000')),
                    ButtonSegment(value: 5000, label: Text('5000')),
                    ButtonSegment(value: 10000, label: Text('10000')),
                  ],
                  selected: {target},
                  onSelectionChanged: (s) => setState(() => target = s.first),
                ),
                const SizedBox(height: 40),
                FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => GameScreen(playerCount: players, target: target)),
                  ),
                  child: const Padding(padding: EdgeInsets.all(12), child: Text('Play vs computer', style: TextStyle(fontSize: 18))),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: _host, child: const Padding(padding: EdgeInsets.all(12), child: Text('Host a game', style: TextStyle(fontSize: 16))))),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton(onPressed: () => _join(), child: const Padding(padding: EdgeInsets.all(12), child: Text('Join with code', style: TextStyle(fontSize: 16))))),
                ]),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _browse,
                  child: const Padding(padding: EdgeInsets.all(12), child: Text('Find open games', style: TextStyle(fontSize: 16))),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Let others find my hosted game', style: TextStyle(fontSize: 14)),
                  value: listPublicly,
                  onChanged: (v) => setState(() => listPublicly = v),
                ),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IntroScreen())), child: const Text('How to play')),
                  TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RulesScreen())), child: const Text('Rules & scores')),
                ]),
                const Text('Build 8', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white54)),
              ],
            ),
          ))),
        ),
      );
}

// ---------------------------------------------------------------- Cards
const _setColors = [
  Color(0xFF8D6E63), Color(0xFFE91E63), Color(0xFFF48FB1), Color(0xFF7E57C2),
  Color(0xFF3F51B5), Color(0xFFD32F2F), Color(0xFFAD1457), Color(0xFF455A64),
  Color(0xFFF9A825), Color(0xFFEF6C00), Color(0xFF2E7D32), Color(0xFF6A1B9A),
];

String _typeLabel(CardType t) {
  switch (t) {
    case CardType.okeiim:
      return '50';
    case CardType.tang:
      return 'tang';
    case CardType.teruich:
      return '10';
    case CardType.kas:
      return 'kas';
  }
}

// Press and hold any card to see it enlarged; release to close.
class CardPreview {
  static OverlayEntry? _entry;

  static void show(BuildContext context, HCard card, {bool scrim = true}) {
    hide();
    final entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: Container(
          color: scrim ? Colors.black54 : Colors.transparent,
          alignment: Alignment.center,
          child: CardView(card: card, width: 230),
        ),
      ),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}

class CardView extends StatelessWidget {
  final HCard card;
  final double width;
  final bool highlight;
  final bool dim;
  final VoidCallback? onTap;
  final bool hover;
  const CardView({super.key, required this.card, this.width = 52, this.highlight = false, this.dim = false, this.onTap, this.hover = false});

  Widget _placeholder() => SizedBox.expand(child: CustomPaint(painter: CardArt(card)));

  @override
  Widget build(BuildContext context) => hover
      ? MouseRegion(
          onEnter: (_) => CardPreview.show(context, card, scrim: false),
          onExit: (_) => CardPreview.hide(),
          child: _body(context),
        )
      : _body(context);

  Widget _body(BuildContext context) => GestureDetector(
        onTap: onTap,
        onLongPressStart: (_) => CardPreview.show(context, card),
        onLongPressEnd: (_) => CardPreview.hide(),
        onLongPressCancel: CardPreview.hide,
        child: Opacity(
          opacity: dim ? 0.4 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: width,
            height: width * 1.6,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: highlight ? Colors.amber : Colors.white24, width: highlight ? 3 : 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(
                'assets/cards/${card.set}_${card.index}.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(),
              ),
            ),
          ),
        ),
      );
}


// ---------------------------------------------------------------- Card art
// Original card faces drawn in code (no image files needed).
// One motif per set; ribbon color shows which tang yak a ribbon belongs to:
//   red ribbon = ksaiak (mases, chudel, babii) or nisoro
//   purple ribbon = chauotang (bara, kob, ska)
//   red ribbon with marks = kodangko (mats, chume, sakura)
class CardArt extends CustomPainter {
  final HCard card;
  CardArt(this.card);

  void _text(Canvas c, String t, Offset o, double size, Color col, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: size, color: col, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o);
  }

  Paint _fill(Color col) => Paint()..color = col;
  Paint _stroke(Color col, double w) => Paint()
    ..color = col
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas c, Size sz) {
    final w = sz.width, h = sz.height;
    c.drawRect(Offset.zero & sz, _fill(const Color(0xFFFFF3D6)));

    // Motif (later cards in a set are slightly smaller / mirrored so they differ).
    final area = Rect.fromLTWH(w * 0.08, h * 0.28, w * 0.84, h * 0.52);
    c.save();
    c.translate(area.center.dx, area.center.dy);
    if (card.index >= 2) c.scale(card.index == 3 ? -0.82 : 0.82, 0.82);
    c.translate(-area.center.dx, -area.center.dy);
    _motif(c, area);
    c.restore();

    _text(c, setNames[card.set], Offset(w * 0.06, h * 0.85), w * 0.19, const Color(0xFF3E2723), bold: true);

    switch (card.type) {
      case CardType.okeiim:
        c.drawRect(Rect.fromLTWH(1.5, 1.5, w - 3, h - 3), _stroke(const Color(0xFFFFB300), 3));
        c.drawCircle(Offset(w * 0.78, h * 0.9), w * 0.16, _fill(const Color(0xFFFFB300)));
        _text(c, '50', Offset(w * 0.66, h * 0.9 - w * 0.12), w * 0.22, Colors.black, bold: true);
        break;
      case CardType.teruich:
        c.drawCircle(Offset(w * 0.78, h * 0.9), w * 0.16, _fill(const Color(0xFF1565C0)));
        _text(c, '10', Offset(w * 0.66, h * 0.9 - w * 0.12), w * 0.2, Colors.white, bold: true);
        break;
      case CardType.tang:
        final purple = const {5, 8, 9}.contains(card.set);
        final poem = card.set <= 2;
        final col = purple ? const Color(0xFF6A1B9A) : const Color(0xFFD32F2F);
        final r = Rect.fromLTWH(w * 0.12, h * 0.07, w * 0.76, h * 0.17);
        c.drawRect(r, _fill(col));
        if (poem) {
          for (var i = 0; i < 3; i++) {
            final x = r.left + r.width * (0.2 + 0.3 * i);
            c.drawLine(Offset(x, r.top + r.height * 0.2), Offset(x, r.bottom - r.height * 0.2), _stroke(Colors.white70, 1.2));
          }
        }
        break;
      case CardType.kas:
        break;
    }
    c.drawRect(Offset.zero & sz, _stroke(Colors.black26, 1));
  }

  void _motif(Canvas c, Rect a) {
    final cx = a.center.dx, cy = a.center.dy;
    final r = min(a.width, a.height) / 2;
    switch (card.set) {
      case 0: // mats: pine
        c.drawRect(Rect.fromCenter(center: Offset(cx, a.bottom - r * 0.15), width: r * 0.25, height: r * 0.5), _fill(const Color(0xFF6D4C41)));
        for (var i = 0; i < 3; i++) {
          final top = a.top + i * r * 0.45;
          final half = r * (0.5 + i * 0.28);
          final p = Path()
            ..moveTo(cx, top)
            ..lineTo(cx - half, top + r * 0.7)
            ..lineTo(cx + half, top + r * 0.7)
            ..close();
          c.drawPath(p, _fill(const Color(0xFF2E7D32)));
        }
        break;
      case 1: // chume: plum blossom branch
        c.drawLine(Offset(a.left, a.bottom), Offset(a.right, a.top + r * 0.2), _stroke(const Color(0xFF5D4037), 3));
        for (var i = 0; i < 4; i++) {
          final o = Offset(a.left + a.width * (0.2 + i * 0.2), a.bottom - a.height * (0.15 + i * 0.2));
          c.drawCircle(o, r * 0.22, _fill(const Color(0xFFE91E63)));
          c.drawCircle(o, r * 0.07, _fill(const Color(0xFFFFEB3B)));
        }
        break;
      case 2: // sakura: five-petal flower
        for (var i = 0; i < 5; i++) {
          final ang = i * 2 * pi / 5 - pi / 2;
          c.drawCircle(Offset(cx + cos(ang) * r * 0.45, cy + sin(ang) * r * 0.45), r * 0.32, _fill(const Color(0xFFF48FB1)));
        }
        c.drawCircle(Offset(cx, cy), r * 0.17, _fill(const Color(0xFFC2185B)));
        break;
      case 3: // mases: hanging wisteria
        for (var s = 0; s < 3; s++) {
          final x = a.left + a.width * (0.2 + s * 0.3);
          for (var i = 0; i < 5; i++) {
            c.drawCircle(Offset(x, a.top + i * a.height * 0.2 + 4), r * (0.2 - i * 0.02), _fill(i.isEven ? const Color(0xFF7E57C2) : const Color(0xFF9575CD)));
          }
        }
        break;
      case 4: // chudel: iris
        for (var i = 0; i < 3; i++) {
          final x = cx + (i - 1) * r * 0.45;
          final p = Path()
            ..moveTo(x, a.bottom)
            ..quadraticBezierTo(x + (i - 1) * r * 0.5, cy, x + (i - 1) * r * 0.9, a.top + r * 0.2);
          c.drawPath(p, _stroke(const Color(0xFF283593), 4));
        }
        c.drawCircle(Offset(cx, a.top + r * 0.35), r * 0.3, _fill(const Color(0xFF5E35B1)));
        break;
      case 5: // bara: peony
        c.drawCircle(Offset(cx, cy), r * 0.9, _fill(const Color(0xFFC62828)));
        c.drawCircle(Offset(cx, cy), r * 0.62, _fill(const Color(0xFFE53935)));
        c.drawCircle(Offset(cx, cy), r * 0.34, _fill(const Color(0xFFEF9A9A)));
        c.drawCircle(Offset(cx, cy), r * 0.12, _fill(const Color(0xFFFFD54F)));
        break;
      case 6: // babii: bush clover
        c.drawLine(Offset(a.left + a.width * 0.2, a.bottom), Offset(a.right - a.width * 0.1, a.top), _stroke(const Color(0xFF558B2F), 3));
        for (var i = 0; i < 6; i++) {
          final t = i / 5;
          final o = Offset(a.left + a.width * (0.2 + 0.7 * t), a.bottom - a.height * t);
          c.drawCircle(o + Offset(i.isEven ? -r * 0.25 : r * 0.25, 0), r * 0.16, _fill(i.isEven ? const Color(0xFFD81B60) : const Color(0xFFAD1457)));
        }
        break;
      case 7: // buil: moon over hills
        c.drawCircle(Offset(cx, cy - r * 0.2), r * 0.55, _fill(Colors.white));
        c.drawCircle(Offset(cx, cy - r * 0.2), r * 0.55, _stroke(const Color(0xFFBDBDBD), 2));
        for (var i = 0; i < 3; i++) {
          final y = a.bottom - i * r * 0.28;
          c.drawArc(Rect.fromLTWH(a.left - r * 0.2, y - r * 0.5, a.width + r * 0.4, r), 3.14159, 3.14159, false, _stroke(const Color(0xFF37474F), 4));
        }
        break;
      case 8: // kob: chrysanthemum
        for (var i = 0; i < 12; i++) {
          c.save();
          c.translate(cx, cy);
          c.rotate(i * pi / 6);
          c.drawOval(Rect.fromCenter(center: Offset(0, -r * 0.5), width: r * 0.28, height: r * 0.6), _fill(i.isEven ? const Color(0xFFFBC02D) : const Color(0xFFF57F17)));
          c.restore();
        }
        c.drawCircle(Offset(cx, cy), r * 0.2, _fill(const Color(0xFFE65100)));
        break;
      case 9: // ska: maple leaf (5-point star shape)
        final p = Path();
        for (var i = 0; i < 10; i++) {
          final rad = i.isEven ? r * 0.95 : r * 0.42;
          final ang = i * pi / 5 - pi / 2;
          final pt = Offset(cx + cos(ang) * rad, cy + sin(ang) * rad);
          i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
        }
        p.close();
        c.drawPath(p, _fill(const Color(0xFFE64A19)));
        c.drawLine(Offset(cx, cy), Offset(cx, a.bottom), _stroke(const Color(0xFF5D4037), 3));
        break;
      case 10: // nisoro: willow
        c.drawLine(Offset(a.left + a.width * 0.15, a.top), Offset(a.right - a.width * 0.15, a.top), _stroke(const Color(0xFF5D4037), 4));
        for (var i = 0; i < 5; i++) {
          final x = a.left + a.width * (0.15 + i * 0.175);
          final p = Path()
            ..moveTo(x, a.top)
            ..quadraticBezierTo(x + (i.isEven ? 8 : -8), cy, x, a.bottom);
          c.drawPath(p, _stroke(const Color(0xFF2E7D32), 3));
        }
        break;
      case 11: // kiri: paulownia
        c.drawLine(Offset(cx, a.bottom), Offset(cx, a.top + r * 0.2), _stroke(const Color(0xFF4A148C), 3));
        for (var i = 0; i < 3; i++) {
          c.drawCircle(Offset(cx + (i - 1) * r * 0.5, a.top + r * 0.35), r * 0.22, _fill(const Color(0xFF8E24AA)));
        }
        c.drawOval(Rect.fromCenter(center: Offset(cx - r * 0.35, cy + r * 0.35), width: r * 0.9, height: r * 0.6), _fill(const Color(0xFF6A1B9A)));
        c.drawOval(Rect.fromCenter(center: Offset(cx + r * 0.35, cy + r * 0.35), width: r * 0.9, height: r * 0.6), _fill(const Color(0xFF4A148C)));
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CardArt old) => old.card != card;
}

// ---------------------------------------------------------------- How to play
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _pc = PageController();
  int _page = 0;

  Widget _label(String t, Widget w) => Column(mainAxisSize: MainAxisSize.min, children: [Text(t, style: const TextStyle(fontSize: 12)), w]);

  Widget _slide(String title, Widget visual, List<String> lines) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          visual,
          const SizedBox(height: 16),
          for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('\u2022  $l', style: const TextStyle(fontSize: 16))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    const plus = Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('+', style: TextStyle(fontSize: 26)));
    const equals = Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('=', style: TextStyle(fontSize: 26)));
    final slides = <Widget>[
      _slide(
        'Match the cards',
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _label('On the table', const CardView(card: HCard(2, 3), width: 64)),
          plus,
          _label('From your hand', const CardView(card: HCard(2, 0), width: 64)),
          equals,
          _label('You take both', const CardView(card: HCard(2, 0), width: 64, highlight: true)),
        ]),
        [
          'There are 12 flowers with 4 cards each. A card matches any card of the same flower.',
          'Play a card from your hand. If it matches a card on the table, you take both.',
          'Then flip the top card of the stack (omkais). If it matches, take both again.',
          'No match? The card stays on the table.',
        ],
      ),
      _slide(
        'Score with combinations',
        Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _label('3 red ribbons: 100', Row(children: const [CardView(card: HCard(3, 1), width: 52), CardView(card: HCard(4, 1), width: 52), CardView(card: HCard(6, 1), width: 52)])),
          ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _label('3 bright cards: 300', Row(children: const [CardView(card: HCard(0, 0), width: 52), CardView(card: HCard(7, 0), width: 52), CardView(card: HCard(11, 0), width: 52)])),
          ]),
        ]),
        [
          'Bright cards are worth 50 (okeiim), ribbons are tang, and animal cards are 10 (teruich).',
          'Collect matching sets, called yaks, to score. Yaks stack, so a big round can score a lot.',
          'Six bright cards (arasi) or seven ribbons (nanatang) lets you end the round early.',
          'See the Scores tab for every yak.',
        ],
      ),
      _slide(
        'A few rules',
        const Icon(Icons.rule, size: 72),
        [
          'Two players get 10 cards each, three get 9, and four (teams sitting across) get 8.',
          'Three cards of one flower on the table form a stack, and whoever holds the fourth takes it all. Four of a kind means a redeal.',
          'Three of one flower in your hand (chitsiobiki) lets you swap one for a new card.',
          'The first player and their partner can see the bottom card of the stack.',
          'First team to the target score wins. The losing team deals next.',
        ],
      ),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF14412A),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(children: [
              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip'))),
              Expanded(child: PageView(controller: _pc, onPageChanged: (i) => setState(() => _page = i), children: slides)),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < slides.length; i++)
                  Container(
                    margin: const EdgeInsets.all(4),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? Colors.amber : Colors.white38),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (_page < slides.length - 1) {
                        _pc.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    child: Padding(padding: const EdgeInsets.all(12), child: Text(_page < slides.length - 1 ? 'Next' : "Let's play", style: const TextStyle(fontSize: 18))),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Rules and scores
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  static const _rules = <List<String>>[
    ['The cards', '48 cards in 12 flowers: mats, chume, sakura, mases, chudel, bara, babii, buil, kob, ska, nisoro and kiri. A card can only capture a card of its own flower.\n\nokeiim (50): the 6 bright cards.\ntang: the 10 ribbon cards.\nteruich (10): the 9 animal and object cards.\nkas: the 23 plain cards.'],
    ['The deal', 'Two players get 10 cards each, three players get 9, and four players get 8. The same number of cards are dealt face up to the table. The rest form the stack.\n\nIn a four-player game, players sitting across from each other are partners.'],
    ['Cutting and the bottom card', 'The player to the dealer\'s right may cut. The player to the left of the dealer plays first, and that player and their partner can see the bottom card of the stack. The other team cannot.'],
    ['Stacks', 'Three cards of one flower on the table at the start form a stack. Whoever plays a card of that flower takes the whole stack. Four cards of one flower on the table means the cards are redealt. Two cards of one flower stay separate and you choose which to take.'],
    ['Chitsiobiki', 'If you are dealt three cards of one flower, you may trade one of them for a card from the stack. Other players may ask to see all three.'],
    ['Taking a turn', '1. Play any card from your hand. If it matches a card on the table, you take both. Otherwise it stays on the table.\n2. Flip the top card of the stack (omkais). If it matches a card on the table, take both. Otherwise it stays on the table.\n3. Play passes clockwise.'],
    ['Ending a round', 'A round ends when all hands are played. Holding arasi or nanatang lets you end the round early, and then only that yak scores.\n\nIf nobody has a yak, the team with the higher total of okeiim and teruich points wins the round. A tie is a tie.'],
    ['Winning', 'Play several rounds until a team reaches the target score, such as 5000. The losing team deals the next round. Yaks stack, so a team can score more than one in a round.'],
  ];

  static const _yaks = <List<String>>[
    ['ksaiak', '100', '3 plain red ribbons (mases, chudel, babii)'],
    ['ippai', '150', 'sakura bright + kob animal, or buil bright + kob animal'],
    ['chauotang', '150', '3 purple ribbons (bara, kob, ska)'],
    ['kodangko', '150', '3 poem ribbons (mats, chume, sakura)'],
    ['nisoro', '200', 'the 3 scoring nisoro cards'],
    ['teppo', '300', 'sakura bright + buil bright + kob animal'],
    ['inoskasio', '300', 'babii, ska and bara animal cards'],
    ['chume mats sakura', '300', 'the bright cards of those three flowers'],
    ['mats kiri bo', '300', 'the bright cards of mats, kiri and buil'],
    ['skok', '500', '4 bright cards: mats, buil, kiri, sakura'],
    ['kokok', '700', '5 bright cards: skok plus nisoro'],
    ['nanatang', '700', 'any 7 ribbons (can end the round)'],
    ['arasi', '1000', 'all 6 bright cards (can end the round)'],
    ['toiak', '10000', 'all 9 teruich cards'],
  ];

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Rules & scores'),
            bottom: const TabBar(tabs: [Tab(text: 'Rules'), Tab(text: 'Scores')]),
          ),
          body: TabBarView(children: [
            ListView(padding: const EdgeInsets.all(16), children: [
              for (final r in _rules) ...[
                Text(r[0], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(r[1], style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 16),
              ],
            ]),
            ListView(padding: const EdgeInsets.all(8), children: [
              const Padding(padding: EdgeInsets.all(8), child: Text('Yaks stack: a team scores every yak it holds.', style: TextStyle(fontSize: 14))),
              for (final y in _yaks)
                Card(
                  child: ListTile(
                    title: Text(y[0], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    subtitle: Text(y[2]),
                    trailing: Text(y[1], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                ),
            ]),
          ]),
        ),
      );
}

// ---------------------------------------------------------------- Find open games
class BrowseGamesScreen extends StatefulWidget {
  const BrowseGamesScreen({super.key});
  @override
  State<BrowseGamesScreen> createState() => _BrowseGamesScreenState();
}

class _BrowseGamesScreenState extends State<BrowseGamesScreen> {
  List<Map<String, dynamic>> games = [];
  bool loading = true, _busy = false;
  String? error;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    try {
      final raw = keyed(await Rtdb.get('openGames'));
      final now = DateTime.now().millisecondsSinceEpoch;
      final out = <Map<String, dynamic>>[];
      for (final e in raw.entries.take(20)) {
        final v = e.value;
        if (v is! Map) continue;
        final t = (v['t'] as num?)?.toInt() ?? 0;
        if (now - t > 3 * 3600 * 1000) continue; // older than 3 hours
        final lobby = await Rtdb.get('rooms/${e.key}/lobby');
        if (lobby is! Map || lobby['started'] == true) continue;
        out.add({
          'code': e.key,
          'host': '${v['host']}',
          'n': (lobby['n'] as num).toInt(),
          'target': (lobby['target'] as num).toInt(),
          'seated': keyed(lobby['seats']).length,
        });
      }
      if (mounted) {
        setState(() {
          games = out;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Could not load games: $e';
        });
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Open games'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent)),
                      if (games.isEmpty && error == null)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No open games right now. Host one, or ask a friend for their code.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
                        ),
                      for (final g in games)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.groups),
                            title: Text("${g['host']}'s game", style: const TextStyle(fontSize: 17)),
                            subtitle: Text('${g['seated']}/${g['n']} players  -  to ${g['target']}'),
                            trailing: FilledButton(onPressed: () => Navigator.pop(context, g['code'] as String), child: const Text('Join')),
                          ),
                        ),
                      const SizedBox(height: 8),
                      const Text('The list refreshes every few seconds.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                    ]),
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------- Lobby
class LobbyScreen extends StatefulWidget {
  final String nick;
  final String code;
  final bool isHost;
  final int mySeat;
  final int n;
  final int target;
  const LobbyScreen({super.key, required this.nick, required this.code, required this.isHost, required this.mySeat, required this.n, required this.target});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late int mySeat = widget.mySeat;
  Map<String, dynamic> seats = {};
  Timer? _t;
  bool _go = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
    _poll();
    _saveSession(false);
  }

  @override
  void dispose() {
    _t?.cancel();
    if (!_go) {
      SessionStore.clear();
      if (widget.isHost) {
        Rtdb.delete('rooms/${widget.code}');
        Rtdb.delete('openGames/${widget.code}');
      } else {
        Rtdb.delete('rooms/${widget.code}/lobby/seats/$mySeat');
      }
    }
    super.dispose();
  }

  void _saveSession(bool inGame) => SessionStore.save(SavedSession(
        code: widget.code,
        nick: widget.nick,
        isHost: widget.isHost,
        seat: mySeat,
        n: widget.n,
        target: widget.target,
        inGame: inGame,
      ));

  Future<void> _poll() async {
    try {
      final l = await Rtdb.get('rooms/${widget.code}/lobby');
      if (!mounted) return;
      if (l is! Map) {
        setState(() => error = 'The host closed this game.');
        return;
      }
      final s = keyed(l['seats']);
      setState(() {
        seats = s;
        error = null;
      });
      if (!widget.isHost && l['started'] == true && !_go) {
        _go = true;
        _t?.cancel();
        _launch(s);
      }
    } catch (_) {}
  }

  void _launch(Map<String, dynamic> s) {
    _saveSession(true);
    final nicks = List<String?>.generate(widget.n, (i) => s['$i']?.toString());
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          playerCount: widget.n,
          target: widget.target,
          online: OnlineConfig(code: widget.code, isHost: widget.isHost, mySeat: mySeat, seatNicks: nicks),
        ),
      ),
    );
  }

  Future<void> _start() async {
    try {
      await Rtdb.patch('rooms/${widget.code}/lobby', {'started': true});
      await Rtdb.delete('openGames/${widget.code}');
    } catch (_) {}
    _go = true;
    _t?.cancel();
    if (mounted) _launch(seats);
  }

  Future<void> _copyInvite() async {
    await Clipboard.setData(ClipboardData(text: 'Join my Hanahuda game! ${inviteLink(widget.code)}  (game code: ${widget.code})'));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite copied. Paste it into a text or chat.')));
  }

  Future<void> _sit(int seat) async {
    if (widget.isHost || seat == mySeat || seats['$seat'] != null) return;
    try {
      await Rtdb.put('rooms/${widget.code}/lobby/seats/$seat', widget.nick);
      await Rtdb.delete('rooms/${widget.code}/lobby/seats/$mySeat');
      if (mounted) setState(() => mySeat = seat);
      _saveSession(false);
    } catch (_) {}
  }

  Widget _seat(int i, {String? teamLabel}) {
    final nick = seats['$i']?.toString();
    final mine = i == mySeat;
    final open = nick == null;
    return Card(
      color: mine ? Colors.amber.withOpacity(0.25) : null,
      child: ListTile(
        leading: Icon(open ? Icons.smart_toy : Icons.person),
        title: Text(open ? 'Open seat (computer plays)' : nick, style: const TextStyle(fontSize: 17)),
        subtitle: teamLabel == null ? null : Text(teamLabel),
        trailing: (!widget.isHost && open) ? const Text('Sit here') : (mine ? const Text('You') : null),
        onTap: (!widget.isHost && open) ? () => _sit(i) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.n;
    final kids = <Widget>[
      const SizedBox(height: 8),
      const Text('Game code', textAlign: TextAlign.center),
      Text(widget.code, textAlign: TextAlign.center, style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold, letterSpacing: 8)),
      const Text('Friends join with this code.', textAlign: TextAlign.center),
      if (widget.isHost)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(onPressed: _copyInvite, icon: const Icon(Icons.copy), label: const Text('Copy invite link')),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(playerCount: widget.n, target: widget.target))),
              icon: const Icon(Icons.smart_toy),
              label: const Text('Practice vs computer'),
            ),
          ]),
        ),
      const SizedBox(height: 16),
    ];
    if (n == 4) {
      kids.addAll([
        const Text('Team A (seats across from each other)', style: TextStyle(fontWeight: FontWeight.w600)),
        _seat(0, teamLabel: 'Host'),
        _seat(2, teamLabel: "Host's teammate"),
        const SizedBox(height: 8),
        const Text('Team B', style: TextStyle(fontWeight: FontWeight.w600)),
        _seat(1),
        _seat(3, teamLabel: "Teammate of seat 2 player"),
      ]);
    } else {
      for (var i = 0; i < n; i++) {
        kids.add(_seat(i, teamLabel: i == 0 ? 'Host' : null));
      }
    }
    kids.add(const SizedBox(height: 12));
    kids.add(Text(
      widget.isHost ? 'Empty seats are played by the computer. Start when everyone is in.' : 'Pick a seat. Sitting across from someone makes you teammates in a 4-player game.',
      textAlign: TextAlign.center,
    ));
    if (error != null) kids.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent))));
    kids.add(const SizedBox(height: 12));
    kids.add(widget.isHost
        ? FilledButton(onPressed: _start, child: const Padding(padding: EdgeInsets.all(12), child: Text('Start game', style: TextStyle(fontSize: 18))))
        : const Center(child: Text('Waiting for the host to start...', style: TextStyle(fontSize: 16))));
    return Scaffold(
      appBar: AppBar(title: Text('Game ${widget.code}')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(padding: const EdgeInsets.all(16), children: kids),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Game
class GameScreen extends StatefulWidget {
  final int playerCount;
  final int target;
  final OnlineConfig? online;
  final Map<String, dynamic>? resume; // host only: restores a game after a reload
  const GameScreen({super.key, required this.playerCount, required this.target, this.online, this.resume});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late Game game;
  final ai = HanahudaAI();
  final Map<int, int> totals = {};
  String message = '';
  HCard? flipped;
  Set<HCard> legal = {};
  Set<HCard> targets = {};
  Completer<HCard>? _handPick;
  Completer<HCard>? _tablePick;

  // ---- online state ----
  final Set<int> _remote = {}; // host: seats played by other people
  Map<int, List<int>> _awaitLegal = {};
  final Map<int, int> _lastAction = {};
  Timer? _clientTimer;
  bool _publishing = false, _dirty = false, _polling = false, _everSaw = false;
  int _ver = 0, _actionN = 0, _noticeId = 0, _misses = 0;
  int? _seenNoticeId;
  bool _flushing = false, _closedShown = false, _resumed = false, _wasMyTurn = false;
  final List<Map<String, dynamic>> _noticeList = [];
  Timer? _reactTimer;
  final Map<int, int> _reactSeen = {};
  String? _bubble;
  Timer? _bubbleTimer;
  HCard? _peekCard; // bottom card of the stack, seen only by the first player and partner
  Set<int> _peekSeats = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final n = widget.playerCount;
    final o = widget.online;
    String nameFor(int i) {
      if (o != null) {
        final nick = i < o.seatNicks.length ? o.seatNicks[i] : null;
        return (nick != null && nick.isNotEmpty) ? nick : 'CPU $i';
      }
      return i == 0 ? 'You' : (n == 4 && i == 2 ? 'Partner' : 'CPU $i');
    }

    game = Game([
      for (var i = 0; i < n; i++) Player(nameFor(i), n == 4 ? i % 2 : i),
    ]);
    for (final t in game.teamPiles.keys) {
      totals[t] = 0;
    }
    if (o != null) {
      for (var i = 1; i < n; i++) {
        if (i < o.seatNicks.length && o.seatNicks[i] != null) _remote.add(i);
      }
    }
    AudioManager.instance.startMusic();
    if (o != null) _reactTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _pollReactions());
    if (o != null && !o.isHost) {
      _clientTimer = Timer.periodic(const Duration(milliseconds: 900), (_) => _pollClient());
      WidgetsBinding.instance.addPostFrameCallback((_) => _pollClient());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _playMatch());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voice?.stop();
    _voiceTick.dispose();
    _clientTimer?.cancel();
    _reactTimer?.cancel();
    _bubbleTimer?.cancel();
    final o = widget.online;
    if (o != null) {
      SessionStore.clear();
      if (o.isHost) {
        // Tell players the game is over, then clean up after they have had time to see the results.
        Rtdb.patch('rooms/${o.code}/state', {'closed': true}).catchError((_) {});
        Future.delayed(const Duration(seconds: 60), () {
          Rtdb.delete('rooms/${o.code}').catchError((_) {});
          Rtdb.delete('openGames/${o.code}').catchError((_) {});
        });
      }
    }
    AudioManager.instance.stopMusic();
    super.dispose();
  }

  /// Coming back from another app or tab: catch up right away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.online != null) {
      _polling = false;
      if (!widget.online!.isHost) _pollClient();
      _pollReactions();
    }
  }

  String teamName(int t) {
    if (widget.playerCount == 4) return t == 0 ? 'Your team' : 'Opponents';
    if (t == 0) return 'You';
    final names = game.players.where((p) => p.team == t).map((p) => p.name).toList();
    return names.isEmpty ? 'CPU $t' : names.join(' & ');
  }

  /// Team label that reads the same for every player (used in shared messages).
  String _tn(int t) {
    if (widget.online == null) return teamName(t);
    final names = game.players.where((p) => p.team == t).map((p) => p.name).toList();
    return names.isEmpty ? 'Team $t' : names.join(' & ');
  }

  Future<void> _delay(int ms) {
    _publish();
    return Future.delayed(Duration(milliseconds: ms));
  }

  void _setNotice(String title, String body, {bool end = false}) {
    _noticeList.add({'id': ++_noticeId, 'title': title, 'body': body, 'end': end});
    if (_noticeList.length > 4) _noticeList.removeAt(0);
    _publish();
  }

  // ---- Host: publish the game so other players can see it ----
  Future<void> _publish() async {
    final o = widget.online;
    if (o == null || !o.isHost) return;
    if (_publishing) {
      _dirty = true;
      return;
    }
    _publishing = true;
    try {
      do {
        _dirty = false;
        _ver++;
        final msg = message.startsWith('Your turn') ? "${game.players[0].name}'s turn" : message;
        final state = <String, Object?>{
          'v': _ver,
          'names': [for (final p in game.players) p.name],
          'teams': [for (final p in game.players) p.team],
          'counts': [for (final p in game.players) p.hand.length],
          'table': [for (final c in game.table) c.id],
          'stack': game.stack.length,
          'piles': {for (final e in game.teamPiles.entries) '${e.key}': [for (final c in e.value) c.id]},
          'current': game.current,
          'dealer': game.dealer,
          'message': msg,
          'flipped': flipped?.id ?? -1,
          'totals': {for (final e in totals.entries) '${e.key}': e.value},
          'notices': _noticeList,
          'peek': (_peekCard != null && game.stack.isNotEmpty && game.stack.first == _peekCard) ? _peekCard!.id : -1,
          'peekSeats': _peekSeats.toList(),
        };
        await Rtdb.put('rooms/${o.code}/state', state);
        for (final seat in _remote) {
          await Rtdb.put('rooms/${o.code}/hands/$seat', {
            'hand': [for (final c in game.players[seat].hand) c.id],
            'legal': _awaitLegal[seat] ?? <int>[],
          });
        }
      } while (_dirty);
    } catch (_) {
    } finally {
      _publishing = false;
    }
  }

  // ---- Host: wait for another person's move ----
  Future<int> _waitRemoteAction(int seat, List<int> legalIds) async {
    final o = widget.online!;
    final clock = Stopwatch()..start();
    while (mounted) {
      try {
        final a = await Rtdb.get('rooms/${o.code}/actions/$seat');
        if (a is Map) {
          final n = (a['n'] as num).toInt();
          final id = (a['id'] as num).toInt();
          if (n > (_lastAction[seat] ?? 0)) {
            _lastAction[seat] = n;
            if (legalIds.contains(id)) return id;
          }
        }
      } catch (_) {}
      if (clock.elapsed.inSeconds > 120) return legalIds.first; // player went away
      await Future.delayed(const Duration(milliseconds: 700));
    }
    return legalIds.first;
  }

  Future<RoundResult?> _remoteTurn(int seat) async {
    final p = game.players[seat];
    final legalCards = game.legalPlays(p);
    final ids = [for (final c in legalCards) c.id];
    _awaitLegal = {seat: ids};
    setState(() => message = "${p.name}'s turn");
    await _publish();
    final id = await _waitRemoteAction(seat, ids);
    _awaitLegal = {};
    if (!mounted) return null;
    final card = legalCards.firstWhere((c) => c.id == id, orElse: () => legalCards.first);
    final opts = game.captureOptions(card);
    setState(() {
      message = '${p.name} plays ${setNames[card.set]}#${card.index}';
      game.playFromHand(card, capture: opts.isEmpty ? null : (opts.length == 1 ? opts.first : (ai.chooseDrawCapture(game, card) ?? opts.first)));
    });
    AudioManager.instance.sfx(opts.isNotEmpty ? 'capture' : 'deal');
    await _delay(500);
    return _flipPhase(human: false);
  }

  // ---- Client: read the host's game and show it from my seat ----
  Future<void> _pollClient() async {
    final o = widget.online;
    if (o == null || _polling || !mounted) return;
    _polling = true;
    try {
      final s = await Rtdb.get('rooms/${o.code}/state');
      final h = await Rtdb.get('rooms/${o.code}/hands/${o.mySeat}');
      if (!mounted) return;
      if (s is Map) {
        _everSaw = true;
        _misses = 0;
        _apply(s, h);
        if (s['closed'] == true && !_closedShown) {
          _closedShown = true;
          _clientTimer?.cancel();
          while (_flushing) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
          if (mounted) {
            await _dialog<void>('Game ended', 'The host ended the game.', (ctx) => [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]);
            if (mounted) Navigator.pop(context);
          }
        }
      } else if (_everSaw && ++_misses >= 3) {
        _clientTimer?.cancel();
        await _dialog<void>('Game ended', 'The host left the game.', (ctx) => [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]);
        if (mounted) Navigator.pop(context);
      }
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  void _apply(Map s, dynamic h) {
    final o = widget.online!;
    final n = widget.playerCount;
    final my = o.mySeat;
    final names = [for (final x in asList(s['names'])) '$x'];
    final teams = [for (final x in asList(s['teams'])) (x as num).toInt()];
    final counts = [for (final x in asList(s['counts'])) (x as num).toInt()];
    if (names.length < n || teams.length < n || counts.length < n) return;
    final tmap = <int, int>{teams[my]: 0};
    var next = 1;
    for (var i = 1; i < n; i++) {
      tmap.putIfAbsent(teams[(my + i) % n], () => next++);
    }
    final players = <Player>[];
    for (var i = 0; i < n; i++) {
      final seat = (my + i) % n;
      final p = Player(names[seat], tmap[teams[seat]]!);
      if (i == 0) {
        p.hand.addAll([for (final id in asIds(h is Map ? h['hand'] : null)) cardFromId(id)]);
      } else {
        p.hand.addAll(List.generate(counts[seat], (_) => const HCard(0, 0)));
      }
      players.add(p);
    }
    final g = Game(players, dealer: ((s['dealer'] as num).toInt() - my + n) % n);
    g.table.addAll(asIds(s['table']).map(cardFromId));
    g.stack.addAll(List.generate((s['stack'] as num).toInt(), (_) => const HCard(0, 0)));
    keyed(s['piles']).forEach((k, v) {
      final t = tmap[int.tryParse(k)];
      if (t != null) g.teamPiles[t]!.addAll(asIds(v).map(cardFromId));
    });
    g.current = ((s['current'] as num).toInt() - my + n) % n;
    final tot = <int, int>{for (final t in g.teamPiles.keys) t: 0};
    keyed(s['totals']).forEach((k, v) {
      final t = tmap[int.tryParse(k)];
      if (t != null) tot[t] = (v as num).toInt();
    });
    final lg = h is Map ? asIds(h['legal']) : <int>[];
    final fl = (s['flipped'] as num?)?.toInt() ?? -1;
    final nowMine = lg.isNotEmpty;
    if (nowMine && !_wasMyTurn) AudioManager.instance.sfx('turn');
    _wasMyTurn = nowMine;
    setState(() {
      game = g;
      totals
        ..clear()
        ..addAll(tot);
      legal = {for (final id in lg) cardFromId(id)};
      flipped = fl >= 0 ? cardFromId(fl) : null;
      message = lg.isNotEmpty ? 'Your turn: play a card' : '${s['message'] ?? ''}';
      final pid = (s['peek'] as num?)?.toInt() ?? -1;
      _peekCard = (pid >= 0 && asIds(s['peekSeats']).contains(my)) ? cardFromId(pid) : null;
    });
    final nl = [for (final x in asList(s['notices'])) if (x is Map) Map<String, dynamic>.from(x)];
    nl.sort((a, b) => (a['id'] as num).compareTo(b['id'] as num));
    if (nl.isNotEmpty) {
      final maxId = (nl.last['id'] as num).toInt();
      if (_seenNoticeId == null) {
        _seenNoticeId = maxId; // just joined: only show a finished match
        if (nl.last['end'] == true) _flushNotices([nl.last]);
      } else {
        final fresh = nl.where((x) => (x['id'] as num).toInt() > _seenNoticeId!).toList();
        if (fresh.isNotEmpty) {
          _seenNoticeId = maxId;
          _flushNotices(fresh);
        }
      }
    }
  }

  /// Shows every result the host sent, in order, even if several arrived between checks.
  Future<void> _flushNotices(List<Map<String, dynamic>> items) async {
    while (_flushing) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    _flushing = true;
    try {
      for (final nt in items) {
        if (!mounted) break;
        await _showNotice('${nt['title']}', '${nt['body']}', nt['end'] == true);
        if (nt['end'] == true) break;
      }
    } finally {
      _flushing = false;
    }
  }

  // ---- Reactions ----
  static const _emojis = ['\u{1F44F}', '\u{1F602}', '\u{1F62E}', '\u{1F525}', '\u{1F622}', '\u{1F44D}', '\u{1F389}', '\u{1F634}', '\u{1F64C}', '\u{1F605}'];

  String _seatName(int seat) {
    final o = widget.online!;
    final n = widget.playerCount;
    final idx = o.isHost ? seat : (seat - o.mySeat + n) % n;
    return (idx >= 0 && idx < game.players.length) ? game.players[idx].name : 'Player';
  }

  void _showBubble(String text) {
    _bubbleTimer?.cancel();
    setState(() => _bubble = text);
    _bubbleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  void _sendReaction(String emoji) {
    final o = widget.online;
    if (o == null) return;
    final n = DateTime.now().millisecondsSinceEpoch;
    _reactSeen[o.mySeat] = n;
    Rtdb.put('rooms/${o.code}/reactions/${o.mySeat}', {'n': n, 'e': emoji}).catchError((_) {});
    _showBubble('You $emoji');
  }

  Future<void> _pollReactions() async {
    final o = widget.online;
    if (o == null || !mounted) return;
    try {
      final r = keyed(await Rtdb.get('rooms/${o.code}/reactions'));
      r.forEach((k, v) {
        final seat = int.tryParse(k);
        if (seat == null || v is! Map || seat == o.mySeat) return;
        final n = (v['n'] as num).toInt();
        final seen = _reactSeen[seat];
        _reactSeen[seat] = n;
        if (seen != null && n > seen && mounted) _showBubble('${_seatName(seat)} ${v['e']}');
      });
    } catch (_) {}
  }

  void _openReactions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (final e in _emojis)
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _sendReaction(e);
                },
                child: Padding(padding: const EdgeInsets.all(8), child: Text(e, style: const TextStyle(fontSize: 34))),
              ),
          ]),
        ),
      ),
    );
  }

  // ---- Voice chat ----
  VoiceChat? _voice;
  final ValueNotifier<int> _voiceTick = ValueNotifier<int>(0);

  Future<void> _joinVoice() async {
    final o = widget.online;
    if (o == null) return;
    final v = VoiceChat(
      code: o.code,
      mySeat: o.mySeat,
      onChanged: () {
        if (mounted) {
          setState(() {});
          _voiceTick.value++;
        }
      },
    );
    _voice = v;
    final ok = await v.start();
    if (!ok) {
      _voice = null;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v.status)));
    }
    if (mounted) setState(() {});
    _voiceTick.value++;
  }

  Future<void> _leaveVoice() async {
    final v = _voice;
    _voice = null;
    await v?.stop();
    if (mounted) setState(() {});
    _voiceTick.value++;
  }

  int _seatOfIndex(int i) {
    final o = widget.online;
    if (o == null) return i;
    return o.isHost ? i : (o.mySeat + i) % widget.playerCount;
  }

  void _openVoice() {
    final o = widget.online;
    if (o == null) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<int>(
        valueListenable: _voiceTick,
        builder: (c, _, __) {
          final v = _voice;
          final humans = [for (var s = 0; s < widget.playerCount; s++) if (s < o.seatNicks.length && o.seatNicks[s] != null) s];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Voice chat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  v == null ? 'Talk with the other players in this game. Your browser or phone will ask to use the microphone.' : v.status,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                if (v != null)
                  for (final s in humans)
                    ListTile(
                      dense: true,
                      leading: Icon(v.speaking.contains(s) ? Icons.graphic_eq : Icons.person, color: v.speaking.contains(s) ? Colors.green : null),
                      title: Text(s == o.mySeat ? 'You' : _seatName(s)),
                      trailing: Text((s == o.mySeat || v.members.contains(s)) ? 'in voice' : 'not in voice', style: const TextStyle(fontSize: 12)),
                    ),
                const SizedBox(height: 8),
                if (v == null)
                  FilledButton.icon(onPressed: _joinVoice, icon: const Icon(Icons.mic), label: const Text('Join voice chat'))
                else
                  Wrap(spacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: () => v.setMuted(!v.muted),
                      icon: Icon(v.muted ? Icons.mic_off : Icons.mic),
                      label: Text(v.muted ? 'Unmute' : 'Mute'),
                    ),
                    OutlinedButton.icon(onPressed: _leaveVoice, icon: const Icon(Icons.call_end), label: const Text('Leave voice')),
                  ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ---- Host: save the game so it can be restored after a reload ----
  void _checkpoint() {
    final o = widget.online;
    if (o == null || !o.isHost) return;
    final cp = <String, Object?>{
      'hands': {for (var i = 0; i < game.players.length; i++) '$i': [for (final c in game.players[i].hand) c.id]},
      'stack': [for (final c in game.stack) c.id],
      'table': [for (final c in game.table) c.id],
      'piles': {for (final e in game.teamPiles.entries) '${e.key}': [for (final c in e.value) c.id]},
      'current': game.current,
      'dealer': game.dealer,
      'totals': {for (final e in totals.entries) '${e.key}': e.value},
      'peekSeats': _peekSeats.toList(),
      'peek': _peekCard?.id ?? -1,
    };
    Rtdb.put('rooms/${o.code}/checkpoint', cp).catchError((_) {});
  }

  void _restore(Map<String, dynamic> cp) {
    final hands = keyed(cp['hands']);
    for (var i = 0; i < game.players.length; i++) {
      game.players[i].hand
        ..clear()
        ..addAll(asIds(hands['$i']).map(cardFromId));
    }
    game.stack
      ..clear()
      ..addAll(asIds(cp['stack']).map(cardFromId));
    game.table
      ..clear()
      ..addAll(asIds(cp['table']).map(cardFromId));
    for (final t in game.teamPiles.keys) {
      game.teamPiles[t]!.clear();
    }
    keyed(cp['piles']).forEach((k, v) {
      final t = int.tryParse(k);
      if (t != null && game.teamPiles[t] != null) game.teamPiles[t]!.addAll(asIds(v).map(cardFromId));
    });
    game.current = (cp['current'] as num).toInt();
    game.dealer = (cp['dealer'] as num).toInt();
    keyed(cp['totals']).forEach((k, v) {
      final t = int.tryParse(k);
      if (t != null) totals[t] = (v as num).toInt();
    });
    _peekSeats = asIds(cp['peekSeats']).toSet();
    final pk = (cp['peek'] as num?)?.toInt() ?? -1;
    _peekCard = pk >= 0 ? cardFromId(pk) : null;
  }

  /// After a restore, ignore moves that were sent before the reload.
  Future<void> _syncActions() async {
    final o = widget.online;
    if (o == null) return;
    try {
      keyed(await Rtdb.get('rooms/${o.code}/actions')).forEach((k, v) {
        final seat = int.tryParse(k);
        if (seat != null && v is Map) _lastAction[seat] = (v['n'] as num).toInt();
      });
    } catch (_) {}
  }

  Future<void> _showNotice(String title, String body, bool end) async {
    await _dialog<void>(title, body, (ctx) => [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(end ? 'OK' : 'Continue'))]);
    if (end && mounted) Navigator.pop(context);
  }

  Future<T?> _dialog<T>(String title, String body, List<Widget> Function(BuildContext) actions) =>
      showDialog<T>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(title: Text(title), content: Text(body), actions: actions(ctx)),
      );

  // ---- Match / round loop ----
  Future<void> _playMatch() async {
    while (mounted) {
      await _playRound();
      if (!mounted) return;
      final best = totals.values.reduce(max);
      if (best >= widget.target) {
        final winners = totals.entries.where((e) => e.value == best).map((e) => _tn(e.key)).join(' & ');
        _setNotice('Match over', '$winners reached ${widget.target}!\n\n${_totalsText()}', end: true);
        await _dialog<void>('Match over', '$winners reached ${widget.target}!\n\n${_totalsText()}',
            (ctx) => [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]);
        if (mounted) Navigator.pop(context);
        return;
      }
    }
  }

  String _totalsText() => totals.entries.map((e) => '${_tn(e.key)}: ${e.value}').join('\n');

  Future<void> _playRound() async {
    final cp = widget.resume;
    if (cp != null && !_resumed) {
      _resumed = true;
      _restore(cp);
      setState(() {
        flipped = null;
        message = 'Game restored. Welcome back!';
      });
      await _syncActions();
      await _delay(800);
    } else {
    game.deal();
    AudioManager.instance.sfx('deal');
    setState(() {
      flipped = null;
      message = 'Me dou kat! ${game.players[game.dealer].name} dealt (merous).';
    });
    await _delay(800);
    await _chitsiobiki();
    final firstSeat = (game.dealer + 1) % game.players.length;
    _peekSeats = {firstSeat, if (game.players.length == 4) (firstSeat + 2) % 4};
    _peekCard = game.stack.isEmpty ? null : game.stack.first;
    if (_peekSeats.contains(0) && _peekCard != null) {
      setState(() => message = 'You can see the bottom card of the stack.');
      await _delay(1200);
    }
    }
    RoundResult? result;
    while (!game.roundOver) {
      _checkpoint();
      final cur = game.current;
      final early = cur == 0 ? await _humanTurn() : (_remote.contains(cur) ? await _remoteTurn(cur) : await _aiTurn());
      if (!mounted) return;
      if (early != null) {
        result = early;
        break;
      }
      game.endTurn();
    }
    result ??= game.scoreRound();
    final r = result;
    r.yakScores.forEach((t, pts) => totals[t] = (totals[t] ?? 0) + pts);
    final lines = StringBuffer();
    for (final e in game.teamPiles.entries) {
      final yaks = scoreYaks(e.value);
      lines.writeln('${_tn(e.key)}: ${r.yakScores[e.key] ?? 0}');
      if (yaks.isNotEmpty) lines.writeln('  ${yaks.keys.join(', ')}');
    }
    if (r.yakScores.values.any((v) => v > 0)) AudioManager.instance.sfx('yak');
    final head = r.winnerTeam == null ? 'Tie' : '${_tn(r.winnerTeam!)} won the round';
    if (!mounted) return;
    setState(() {});
    _setNotice(head, '$lines\nTotals\n${_totalsText()}');
    await _dialog<void>(head, '$lines\nTotals\n${_totalsText()}',
        (ctx) => [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Next round'))]);
    game.nextRound(r);
  }

  // ---- Chitsiobiki ----
  Future<void> _chitsiobiki() async {
    for (var i = 0; i < game.players.length; i++) {
      final p = game.players[i];
      final sets = game.chitsiobikiSets(p);
      if (sets.isEmpty || !mounted) continue;
      if (i == 0) {
        final cards = p.hand.where((c) => c.set == sets.first).toList();
        final give = await showDialog<HCard?>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Chitsiobiki!'),
            content: Text('You have three ${setNames[sets.first]} cards. Trade one for a new card?'),
            actions: [
              for (final c in cards)
                TextButton(onPressed: () => Navigator.pop(ctx, c), child: Text('Trade ${setNames[c.set]}#${c.index} (${_typeLabel(c.type)})')),
              TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Keep')),
            ],
          ),
        );
        if (give != null) setState(() => game.tradeChitsiobiki(p, give));
      } else {
        final give = ai.chitsiobikiGive(game, p);
        if (give != null) {
          setState(() {
            game.tradeChitsiobiki(p, give);
            message = '${p.name}: ngak a chitsiobiki!';
          });
          await _delay(900);
        }
      }
    }
  }

  // ---- Turns ----
  Future<RoundResult?> _humanTurn() async {
    final p = game.players[0];
    setState(() {
      legal = game.legalPlays(p).toSet();
      message = 'Your turn: play a card';
    });
    AudioManager.instance.sfx('turn');
    _handPick = Completer<HCard>();
    final card = await _handPick!.future;
    if (!mounted) return null;
    setState(() => legal = {});
    final opts = game.captureOptions(card);
    HCard? cap;
    if (opts.length == 1) {
      cap = opts.first;
    } else if (opts.length > 1) {
      setState(() {
        targets = opts.toSet();
        message = 'Tap the table card to capture';
      });
      _tablePick = Completer<HCard>();
      cap = await _tablePick!.future;
      if (!mounted) return null;
      setState(() => targets = {});
    }
    setState(() => game.playFromHand(card, capture: cap));
    AudioManager.instance.sfx(cap != null ? 'capture' : 'deal');
    await _delay(500);
    return _flipPhase(human: true);
  }

  Future<RoundResult?> _aiTurn() async {
    final p = game.currentPlayer;
    final m = ai.chooseMove(game);
    setState(() => message = '${p.name} plays ${setNames[m.card.set]}#${m.card.index}');
    await _delay(800);
    if (!mounted) return null;
    setState(() => game.playFromHand(m.card, capture: m.capture));
    AudioManager.instance.sfx(m.capture != null ? 'capture' : 'deal');
    await _delay(500);
    return _flipPhase(human: false);
  }

  Future<RoundResult?> _flipPhase({required bool human}) async {
    final drawn = game.omkais();
    if (drawn != null) {
      setState(() {
        flipped = drawn;
        message = 'Omkais! ${setNames[drawn.set]}#${drawn.index}';
      });
      await _delay(900);
      if (!mounted) return null;
      final opts = game.captureOptions(drawn);
      HCard? cap;
      if (opts.length == 1) {
        cap = opts.first;
      } else if (opts.length > 1) {
        if (human) {
          setState(() {
            targets = opts.toSet();
            message = 'Omkais: tap the card to capture';
          });
          _tablePick = Completer<HCard>();
          cap = await _tablePick!.future;
          if (!mounted) return null;
          setState(() => targets = {});
        } else {
          cap = ai.chooseDrawCapture(game, drawn);
        }
      }
      setState(() => game.resolveDraw(capture: cap));
      AudioManager.instance.sfx(cap != null ? 'capture' : 'flip');
      await _delay(500);
      if (!mounted) return null;
      setState(() => flipped = null);
    }
    final team = game.currentPlayer.team;
    if (human) {
      if (game.canCallEarlyEnd(team)) {
        final yaks = scoreYaks(game.teamPiles[team]!);
        final name = yaks.containsKey('arasi') ? 'arasi' : 'nanatang';
        final end = await _dialog<bool>(
          'You have $name!',
          'End the round now? Only $name (${yaks[name]}) would score.',
          (ctx) => [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep playing')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('End round')),
          ],
        );
        if (end == true) return game.endRoundEarly(team);
      }
    } else if (ai.shouldCallEarlyEnd(game)) {
      return game.endRoundEarly(team);
    }
    return null;
  }

  // ---- Input ----
  void _onHandTap(HCard c) {
    final o = widget.online;
    if (o != null && !o.isHost) {
      if (legal.contains(c)) {
        setState(() => legal = {});
        Rtdb.put('rooms/${o.code}/actions/${o.mySeat}', {'n': ++_actionN, 'id': c.id}).catchError((_) {});
      }
      return;
    }
    final p = _handPick;
    if (p != null && !p.isCompleted && legal.contains(c)) p.complete(c);
  }

  void _onTableTap(HCard c) {
    final p = _tablePick;
    if (p != null && !p.isCompleted && targets.contains(c)) p.complete(c);
  }

  // ---- Build ----
  Widget _pileColumn(String label, List<HCard> cards, double cw) {
    final step = cw * 0.4;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label (${cards.length})', style: TextStyle(fontSize: _compact ? 12 : 14)),
          SizedBox(
            width: cw + 6 + max(0, cards.length - 1) * step,
            height: cw * 1.6 + 6,
            child: Stack(children: [
              for (var i = 0; i < cards.length; i++) Positioned(left: i * step, child: CardView(card: cards[i], width: cw, hover: true)),
            ]),
          ),
        ],
      ),
    );
  }

  void _showPile(int team) {
    final pile = game.teamPiles[team]!;
    Widget section(String label, CardType t) {
      final cards = pile.where((c) => c.type == t).toList();
      if (cards.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('$label (${cards.length})', style: const TextStyle(fontWeight: FontWeight.w600))),
        Wrap(children: [for (final c in cards) CardView(card: c, width: 44, hover: true)]),
      ]);
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${teamName(team)} captured (${pile.length})'),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            section('okeiim', CardType.okeiim),
            section('tang', CardType.tang),
            section('teruich', CardType.teruich),
            section('kas', CardType.kas),
            const Padding(padding: EdgeInsets.only(top: 10), child: Text('Press and hold a card to enlarge it.', style: TextStyle(fontSize: 11))),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  /// Captured cards of any team. Visible to everyone, as at a real table.
  Widget _teamPile(int team, {double cardW = 26}) {
    final pile = game.teamPiles[team]!;
    List<HCard> of(CardType t) => pile.where((c) => c.type == t).toList();
    final yaks = scoreYaks(pile);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _showPile(team),
      child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.all(_compact ? 3 : 6),
      decoration: BoxDecoration(
        border: Border.all(color: team == 0 ? Colors.amber.withOpacity(0.6) : Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text('${teamName(team)} captured (${pile.length})', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: _compact ? 14 : 16, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: 'Enlarge',
            iconSize: _compact ? 18 : 24,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.zoom_out_map),
            onPressed: () => _showPile(team),
          ),
        ]),
        _centeredRow([
          _pileColumn('okeiim', of(CardType.okeiim), cardW),
          _pileColumn('tang', of(CardType.tang), cardW),
          _pileColumn('teruich', of(CardType.teruich), cardW),
          _pileColumn('kas', of(CardType.kas), cardW),
        ], cross: CrossAxisAlignment.start),
        if (yaks.isNotEmpty) Text('Yaks: ${yaks.keys.join(', ')}', style: TextStyle(color: Colors.amber, fontSize: _compact ? 12 : 15)),
      ]),
    ));
  }

  Widget _opponents() => Wrap(
        alignment: WrapAlignment.center,
        spacing: _compact ? 6 : 12,
        runSpacing: 0,
        children: [
          for (var i = 1; i < game.players.length; i++)
            Chip(
              backgroundColor: game.current == i ? Colors.amber.withOpacity(0.35) : null,
              visualDensity: _compact ? VisualDensity.compact : VisualDensity.standard,
              avatar: (_voice?.speaking.contains(_seatOfIndex(i)) ?? false) ? const Icon(Icons.graphic_eq, size: 18, color: Colors.greenAccent) : null,
              label: Text('${game.players[i].name}  ${game.players[i].hand.length} cards', style: TextStyle(fontSize: _compact ? 13 : 16)),
            ),
        ],
      );

  // Responsive sizes, set on every build.
  double _tw = 52, _hw = 56, _pwMine = 28, _pwOpp = 22;
  bool _compact = false; // phone-sized layout

  /// A row that is centered when it fits and scrolls sideways when it does not.
  Widget _centeredRow(List<Widget> kids, {CrossAxisAlignment cross = CrossAxisAlignment.center}) => LayoutBuilder(
        builder: (ctx, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: cross, children: kids),
          ),
        ),
      );

  bool get _showPeek {
    final o = widget.online;
    if (o != null && !o.isHost) return _peekCard != null;
    return _peekCard != null && _peekSeats.contains(0) && game.stack.isNotEmpty && game.stack.first == _peekCard;
  }

  double _groupWidth(List<HCard> g) => g.length == 1 ? _tw + 4 : _tw + 8 + (g.length - 1) * _tw * 0.3;

  /// The draw stack sits in the middle of the table and the table cards are laid around it.
  Widget _tableArea() => LayoutBuilder(builder: (ctx, box) {
        final cw = _tw, ch = _tw * 1.6;
        final cx = box.maxWidth / 2, cy = box.maxHeight / 2;
        final rx = max(40.0, box.maxWidth / 2 - cw * 0.9);
        final ry = max(ch * 1.05, min(box.maxHeight / 2 - ch * 0.7, rx * 0.95));
        final groups = _tableGroups();
        final n = groups.length;
        final peekW = cw * 0.75;
        final stackLeft = cx - cw / 2;
        final kids = <Widget>[
          Positioned(
            left: stackLeft,
            top: cy - ch / 2,
            child: Container(
              width: cw,
              height: ch,
              decoration: BoxDecoration(color: Colors.green.shade900, borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.white54, width: 2)),
              child: Center(child: Text('${game.stack.length}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
            ),
          ),
          if (flipped != null) Positioned(left: stackLeft + cw + 8, top: cy - ch / 2, child: CardView(card: flipped!, width: cw, highlight: true)),
          if (_showPeek)
            Positioned(
              left: stackLeft - peekW - 14,
              top: cy - peekW * 0.8,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Bottom card', style: TextStyle(fontSize: 12)),
                CardView(card: _peekCard!, width: peekW, hover: true),
              ]),
            ),
        ];
        for (var i = 0; i < n; i++) {
          final g = groups[i];
          final ang = -pi / 2 + 2 * pi * i / n;
          kids.add(AnimatedPositioned(
            key: ValueKey('tg${g.first.id}'),
            duration: const Duration(milliseconds: 250),
            left: cx + rx * cos(ang) - _groupWidth(g) / 2,
            top: cy + ry * sin(ang) - ch / 2,
            child: _tableGroup(g),
          ));
        }
        return SizedBox(width: box.maxWidth, height: box.maxHeight, child: Stack(clipBehavior: Clip.none, children: kids));
      });

  Widget _handRow(List<HCard> hand) => SizedBox(
        height: _hw * 1.6 + 8,
        child: _centeredRow([
          for (final c in hand)
            CardView(card: c, width: _hw, highlight: legal.contains(c) && game.table.any((t) => t.set == c.set), onTap: () => _onHandTap(c)),
        ]),
      );

  List<List<HCard>> _tableGroups() {
    final bySet = <int, List<HCard>>{};
    for (final c in game.table) {
      bySet.putIfAbsent(c.set, () => []).add(c);
    }
    // Only three of a set form a stack; one or two stay as separate cards.
    final out = <List<HCard>>[];
    for (final g in bySet.values) {
      if (g.length >= 3) {
        out.add(g);
      } else {
        for (final c in g) {
          out.add([c]);
        }
      }
    }
    return out;
  }

  /// Cards of the same set on the table are drawn stacked together.
  Widget _tableGroup(List<HCard> g) {
    final head = g.first;
    final hi = targets.contains(head);
    final dim = targets.isNotEmpty && !hi;
    final w = _tw;
    if (g.length == 1) return CardView(card: head, width: w, highlight: hi, dim: dim, onTap: () => _onTableTap(head));
    final step = w * 0.3;
    return GestureDetector(
      onTap: () => _onTableTap(head),
      child: SizedBox(
        width: w + 8 + (g.length - 1) * step,
        height: w * 1.6 + 4,
        child: Stack(children: [
          for (var i = 0; i < g.length; i++) Positioned(left: i * step, child: CardView(card: g[i], width: w, highlight: hi, dim: dim)),
        ]),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('Music: ${AudioManager.instance.musicStatus}\nSound: ${AudioManager.instance.sfxStatus}', style: const TextStyle(fontSize: 11)),
            ),
            SwitchListTile(
              title: const Text('Music'),
              value: AudioManager.instance.musicOn,
              onChanged: (v) async {
                await AudioManager.instance.setMusic(v);
                setSheet(() {});
              },
            ),
            SwitchListTile(
              title: const Text('Sound effects'),
              value: AudioManager.instance.sfxOn,
              onChanged: (v) {
                AudioManager.instance.sfxOn = v;
                setSheet(() {});
              },
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hand = game.players[0].hand;
    return PopScope(
      canPop: widget.online == null,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave this game?'),
            content: Text(widget.online!.isHost ? 'You are the host, so leaving ends the game for everyone.' : 'You can rejoin from the start screen while the game is still running.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
            ],
          ),
        );
        if (leave == true && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(totals.entries.map((e) => '${teamName(e.key)} ${e.value}').join('  |  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          Text('First to ${widget.target}', style: const TextStyle(fontSize: 12)),
        ]),
        actions: [
          if (widget.online != null) IconButton(tooltip: 'Reactions', icon: const Icon(Icons.emoji_emotions_outlined), onPressed: _openReactions),
          if (widget.online != null)
            IconButton(
              tooltip: 'Voice chat',
              icon: Icon(_voice == null ? Icons.mic_none : (_voice!.muted ? Icons.mic_off : Icons.mic), color: _voice == null ? null : (_voice!.muted ? Colors.redAccent : Colors.greenAccent)),
              onPressed: _openVoice,
            ),
          IconButton(tooltip: 'Rules and scores', icon: const Icon(Icons.menu_book), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RulesScreen()))),
          IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings), onPressed: _openSettings),
        ],
      ),
      body: Stack(children: [
        Positioned.fill(child: gameBackground()),
        SafeArea(
          child: LayoutBuilder(builder: (ctx, box) {
            const wide = false; // same phone-style column on every screen
            _compact = !wide;
            final h = box.maxHeight;
            final w = min(box.maxWidth, 620.0);
            if (wide) {
              _tw = (h * 0.12).clamp(48.0, 90.0).toDouble();
              _hw = (h * 0.14).clamp(52.0, 100.0).toDouble();
              _pwOpp = (h * 0.095).clamp(36.0, 64.0).toDouble();
              _pwMine = (h * 0.095).clamp(36.0, 64.0).toDouble();
            } else {
              _tw = min(w / 8, (h - 400) / 5.0).clamp(32.0, 62.0).toDouble();
              _hw = (w / 7).clamp(44.0, 66.0).toDouble();
              _pwOpp = (w / 14).clamp(22.0, 32.0).toDouble();
              _pwMine = (w / 11.5).clamp(26.0, 40.0).toDouble();
            }
            final oppPiles = [for (final t in game.teamPiles.keys.where((t) => t != 0)) _teamPile(t, cardW: _pwOpp)];
            final board = Column(children: [
              const SizedBox(height: 4),
              _opponents(),
              const SizedBox(height: 4),
              if (!wide)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: oppPiles.length > 1 ? 210 : 160),
                  child: SingleChildScrollView(child: Column(children: oppPiles)),
                ),
              Expanded(child: _tableArea()),
              Padding(
                padding: EdgeInsets.symmetric(vertical: wide ? 6 : 2),
                child: Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: wide ? 16 : 15, fontWeight: FontWeight.w600)),
              ),
              if (!wide) _teamPile(0, cardW: _pwMine),
              const SizedBox(height: 6),
              _handRow(hand),
              const SizedBox(height: 6),
            ]);
            final panelW = min(w * 0.31, 460.0);
            final content = wide
                ? Row(children: [
                    SizedBox(
                      width: panelW,
                      child: Center(child: SingleChildScrollView(child: Column(children: oppPiles))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: board),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: panelW,
                      child: Center(child: SingleChildScrollView(child: _teamPile(0, cardW: _pwMine))),
                    ),
                  ])
                : board;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: content),
              ),
            );
          }),
        ),
        // Hidden players that carry other people's voices.
        if (_voice != null) ..._voice!.audioViews(),
        // Glowing border when it is your turn.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(border: Border.all(color: legal.isNotEmpty ? Colors.amberAccent : Colors.transparent, width: 6)),
            ),
          ),
        ),
        // Reaction pop-up.
        if (_bubble != null)
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(24)),
                  child: Text(_bubble!, style: const TextStyle(fontSize: 24)),
                ),
              ),
            ),
          ),
      ]),
    ));
  }
}
