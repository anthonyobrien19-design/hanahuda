// Palauan Hanahuda - Flutter UI.
// Files needed in lib/: main.dart, hanahuda_engine.dart, hanahuda_ai.dart
// Card art (optional): assets/cards/<set>_<index>.png, e.g. 0_0.png ... 11_3.png.
// Without art, cards draw as colored placeholders.
import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'hanahuda_engine.dart';
import 'hanahuda_ai.dart';

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

  Future<void> startMusic() async {
    if (!musicOn) return;
    try {
      await _music.setReleaseMode(ReleaseMode.loop);
      await _music.setVolume(0.4);
      await _music.play(AssetSource('music/theme.mp3'));
      _started = true;
      musicStatus = 'playing assets/music/theme.mp3';
    } catch (e) {
      musicStatus = 'cannot play assets/music/theme.mp3: $e';
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

Widget gameBackground() => Stack(fit: StackFit.expand, children: [
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

class _SetupScreenState extends State<SetupScreen> {
  int players = 2;
  int target = 5000;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
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
                  child: const Padding(padding: EdgeInsets.all(12), child: Text('Start', style: TextStyle(fontSize: 18))),
                ),
              ],
            ),
          ),
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

  static void show(BuildContext context, HCard card) {
    hide();
    final entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: Container(
          color: Colors.black54,
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
  const CardView({super.key, required this.card, this.width = 52, this.highlight = false, this.dim = false, this.onTap});

  Widget _placeholder() => SizedBox.expand(child: CustomPaint(painter: CardArt(card)));

  @override
  Widget build(BuildContext context) => GestureDetector(
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

// ---------------------------------------------------------------- Game
class GameScreen extends StatefulWidget {
  final int playerCount;
  final int target;
  const GameScreen({super.key, required this.playerCount, required this.target});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final Game game;
  final ai = HanahudaAI();
  final Map<int, int> totals = {};
  String message = '';
  HCard? flipped;
  Set<HCard> legal = {};
  Set<HCard> targets = {};
  Completer<HCard>? _handPick;
  Completer<HCard>? _tablePick;

  @override
  void initState() {
    super.initState();
    final n = widget.playerCount;
    game = Game([
      for (var i = 0; i < n; i++) Player(i == 0 ? 'You' : (n == 4 && i == 2 ? 'Partner' : 'CPU $i'), n == 4 ? i % 2 : i),
    ]);
    for (final t in game.teamPiles.keys) {
      totals[t] = 0;
    }
    AudioManager.instance.startMusic();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playMatch());
  }

  @override
  void dispose() {
    AudioManager.instance.stopMusic();
    super.dispose();
  }

  String teamName(int t) {
    if (t == 0) return widget.playerCount == 4 ? 'Your team' : 'You';
    return widget.playerCount == 4 ? 'Opponents' : 'CPU $t';
  }

  Future<void> _delay(int ms) => Future.delayed(Duration(milliseconds: ms));

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
        final winners = totals.entries.where((e) => e.value == best).map((e) => teamName(e.key)).join(' & ');
        await _dialog<void>('Match over', '$winners reached ${widget.target}!\n\n${_totalsText()}',
            (ctx) => [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]);
        if (mounted) Navigator.pop(context);
        return;
      }
    }
  }

  String _totalsText() => totals.entries.map((e) => '${teamName(e.key)}: ${e.value}').join('\n');

  Future<void> _playRound() async {
    game.deal();
    AudioManager.instance.sfx('deal');
    setState(() {
      flipped = null;
      message = 'Me dou kat! ${game.players[game.dealer].name} dealt (merous).';
    });
    await _delay(800);
    await _chitsiobiki();
    RoundResult? result;
    while (!game.roundOver) {
      final isHuman = game.current == 0;
      final early = isHuman ? await _humanTurn() : await _aiTurn();
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
      lines.writeln('${teamName(e.key)}: ${r.yakScores[e.key] ?? 0}');
      if (yaks.isNotEmpty) lines.writeln('  ${yaks.keys.join(', ')}');
    }
    if (r.yakScores.values.any((v) => v > 0)) AudioManager.instance.sfx('yak');
    final head = r.winnerTeam == null ? 'Tie' : '${teamName(r.winnerTeam!)} won the round';
    if (!mounted) return;
    setState(() {});
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
          Text('$label (${cards.length})', style: const TextStyle(fontSize: 11)),
          SizedBox(
            width: cw + 6 + max(0, cards.length - 1) * step,
            height: cw * 1.6 + 6,
            child: Stack(children: [
              for (var i = 0; i < cards.length; i++) Positioned(left: i * step, child: CardView(card: cards[i], width: cw)),
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
        Wrap(children: [for (final c in cards) CardView(card: c, width: 44)]),
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: team == 0 ? Colors.amber.withOpacity(0.6) : Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => _showPile(team),
          child: Text('${teamName(team)} captured (${pile.length})  - tap to enlarge', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _pileColumn('okeiim', of(CardType.okeiim), cardW),
            _pileColumn('tang', of(CardType.tang), cardW),
            _pileColumn('teruich', of(CardType.teruich), cardW),
            _pileColumn('kas', of(CardType.kas), cardW),
          ]),
        ),
        if (yaks.isNotEmpty) Text('Yaks: ${yaks.keys.join(', ')}', style: const TextStyle(color: Colors.amber, fontSize: 12)),
      ]),
    );
  }

  Widget _opponents() => Wrap(
        spacing: 12,
        children: [
          for (var i = 1; i < game.players.length; i++)
            Chip(
              backgroundColor: game.current == i ? Colors.amber.withOpacity(0.35) : null,
              label: Text('${game.players[i].name}  ${game.players[i].hand.length} cards'),
            ),
        ],
      );

  List<List<HCard>> _tableGroups() {
    final bySet = <int, List<HCard>>{};
    for (final c in game.table) {
      bySet.putIfAbsent(c.set, () => []).add(c);
    }
    return bySet.values.toList();
  }

  /// Cards of the same set on the table are drawn stacked together.
  Widget _tableGroup(List<HCard> g) {
    final head = g.first;
    final hi = targets.contains(head);
    final dim = targets.isNotEmpty && !hi;
    if (g.length == 1) return CardView(card: head, highlight: hi, dim: dim, onTap: () => _onTableTap(head));
    const step = 16.0;
    const w = 52.0;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(totals.entries.map((e) => '${teamName(e.key)} ${e.value}').join('  |  '), style: const TextStyle(fontSize: 14)),
        actions: [
          Center(child: Text('to ${widget.target}')),
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
        ],
      ),
      body: Stack(children: [
        Positioned.fill(child: gameBackground()),
        SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _opponents(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (final t in game.teamPiles.keys.where((t) => t != 0)) _teamPile(t, cardW: 22),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 52,
                        height: 83,
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(color: Colors.green.shade900, borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.white24)),
                        child: Center(child: Text('${game.stack.length}')),
                      ),
                      if (flipped != null) CardView(card: flipped!, highlight: true),
                    ]),
                    const SizedBox(height: 6),
                    const Text('Table', style: TextStyle(fontSize: 12)),
                    Wrap(children: [
                      for (final g in _tableGroups()) _tableGroup(g),
                    ]),
                  ]),
                ),
              ),
              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(message, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              _teamPile(0, cardW: 28),
              const SizedBox(height: 6),
              SizedBox(
                height: 96,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final c in hand)
                    CardView(card: c, width: 56, highlight: legal.contains(c), dim: legal.isNotEmpty && !legal.contains(c), onTap: () => _onHandTap(c)),
                ]),
              ),
            ],
          ),
        ),
      ),
      ]),
    );
  }
}
