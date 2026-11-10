// Palauan Hanahuda game engine (pure Dart, no Flutter dependency).
import 'dart:math';

const setNames = [
  'mats', 'chume', 'sakura', 'mases', 'chudel', 'bara',
  'babii', 'buil', 'kob', 'ska', 'nisoro', 'kiri',
];

enum CardType { okeiim, tang, teruich, kas }

CardType _typeOf(int s, int i) {
  const okeiimSets = {0, 1, 2, 7, 10, 11};
  if (i == 0 && okeiimSets.contains(s)) return CardType.okeiim;
  if (s == 7 || s == 11) return i == 1 ? CardType.teruich : CardType.kas;
  if (s == 10) {
    return i == 1 ? CardType.teruich : (i == 2 ? CardType.tang : CardType.kas);
  }
  if (s <= 2) return i == 1 ? CardType.tang : CardType.kas;
  if (i == 0) return CardType.teruich; // mases, chudel, bara, babii, kob, ska
  if (i == 1) return CardType.tang;
  return CardType.kas;
}

class HCard {
  final int set; // 0..11, order of setNames
  final int index; // 0..3, order shown on the page
  const HCard(this.set, this.index);
  int get id => set * 4 + index;
  CardType get type => _typeOf(set, index);
  int get points => type == CardType.okeiim ? 50 : (type == CardType.teruich ? 10 : 0);
  @override
  bool operator ==(Object o) => o is HCard && o.id == id;
  @override
  int get hashCode => id;
  @override
  String toString() => '${setNames[set]}#$index(${type.name})';
}

List<HCard> fullDeck() =>
    [for (var s = 0; s < 12; s++) for (var i = 0; i < 4; i++) HCard(s, i)];

class Player {
  final String name;
  final int team; // 2 players: own team each. 4 players: seats 0&2 = team 0, 1&3 = team 1
  final List<HCard> hand = [];
  Player(this.name, this.team);
}

class RoundResult {
  final Map<int, int> yakScores; // team -> points
  final int? winnerTeam; // null = tie
  RoundResult(this.yakScores, this.winnerTeam);
}

class Game {
  final List<Player> players; // seated clockwise
  final List<HCard> stack = [];
  final List<HCard> table = [];
  final Map<int, List<HCard>> teamPiles = {};
  int dealer;
  int current = 0;
  HCard? _pendingDraw;

  Game(this.players, {this.dealer = 0}) {
    assert(players.length >= 2 && players.length <= 4);
    for (final p in players) {
      teamPiles.putIfAbsent(p.team, () => []);
    }
  }

  static int handSize(int n) => n == 2 ? 10 : (n == 3 ? 9 : 8);

  /// Shuffle and deal. Optional [cutCount] models the cutter's cut (the
  /// cut cards go to the middle of the table first); the UI decides the order.
  /// Redeals automatically if four cards of one set land on the table.
  void deal({Random? rng}) {
    while (true) {
      _dealOnce(rng);
      final counts = <int, int>{};
      for (final c in table) {
        counts[c.set] = (counts[c.set] ?? 0) + 1;
      }
      if (!counts.values.any((n) => n >= 4)) break;
    }
  }

  void _dealOnce(Random? rng) {
    final deck = fullDeck()..shuffle(rng);
    stack.clear();
    table.clear();
    for (final p in players) {
      p.hand.clear();
    }
    for (final t in teamPiles.values) {
      t.clear();
    }
    final h = handSize(players.length);
    for (final p in players) {
      p.hand.addAll(deck.sublist(0, h));
      deck.removeRange(0, h);
    }
    table.addAll(deck.sublist(0, h));
    deck.removeRange(0, h);
    stack.addAll(deck);
    current = (dealer + 1) % players.length; // left of dealer, then clockwise
    _pendingDraw = null;
  }

  // ---- Chitsiobiki: three cards of one set in hand ----
  List<int> chitsiobikiSets(Player p) {
    final counts = <int, int>{};
    for (final c in p.hand) {
      counts[c.set] = (counts[c.set] ?? 0) + 1;
    }
    return [for (final e in counts.entries) if (e.value >= 3) e.key];
  }

  /// Trade [give] for the top card of the stack.
  void tradeChitsiobiki(Player p, HCard give) {
    assert(chitsiobikiSets(p).contains(give.set));
    p.hand.remove(give);
    p.hand.add(stack.removeLast());
    stack.insert(0, give);
  }

  // ---- Turn ----
  Player get currentPlayer => players[current];

  /// Forced capture: if any hand card matches a table card, only those may be played.
  /// When false (default) any hand card may be played; a card that matches a table
  /// set captures it. When true, a matching card must be played if one exists.
  bool mustCapture = false;

  List<HCard> legalPlays(Player p) {
    if (!mustCapture) return List.of(p.hand);
    final m = p.hand.where((c) => table.any((t) => t.set == c.set)).toList();
    return m.isNotEmpty ? m : List.of(p.hand);
  }

  /// Same-set cards on the table form a stack (2 or 3 can appear after the deal).
  /// When [stackTakesAll] is true, capturing takes the whole stack.
  bool stackTakesAll = true;

  List<HCard> stackOf(int set) => table.where((t) => t.set == set).toList();

  List<HCard> captureOptions(HCard c) {
    final m = stackOf(c.set);
    return (stackTakesAll && m.isNotEmpty) ? [m.first] : m;
  }

  /// Step 1: play a card from hand. If a match exists, [capture] must be chosen.
  void playFromHand(HCard card, {HCard? capture}) {
    final p = currentPlayer;
    if (!legalPlays(p).contains(card)) throw StateError('Illegal play');
    p.hand.remove(card);
    final opts = captureOptions(card);
    if (opts.isEmpty) {
      table.add(card);
    } else {
      if (capture == null || !opts.contains(capture)) {
        throw StateError('Must capture a matching card');
      }
      final taken = stackTakesAll ? stackOf(card.set) : [capture];
      table.removeWhere(taken.contains);
      teamPiles[p.team]!..add(card)..addAll(taken);
    }
  }

  /// Step 2 (omkais): flip the top stack card. Returns null if stack is empty.
  HCard? omkais() {
    if (stack.isEmpty) return null;
    _pendingDraw = stack.removeLast();
    return _pendingDraw;
  }

  /// Step 3: resolve the flipped card. Capture is mandatory when a match exists.
  void resolveDraw({HCard? capture}) {
    final d = _pendingDraw;
    if (d == null) return;
    final opts = captureOptions(d);
    if (opts.isEmpty) {
      table.add(d);
    } else {
      if (capture == null || !opts.contains(capture)) {
        throw StateError('Must capture a matching card');
      }
      final taken = stackTakesAll ? stackOf(d.set) : [capture];
      table.removeWhere(taken.contains);
      teamPiles[currentPlayer.team]!..add(d)..addAll(taken);
    }
    _pendingDraw = null;
  }

  void endTurn() => current = (current + 1) % players.length;

  bool get roundOver => players.every((p) => p.hand.isEmpty);

  // ---- Early end ----
  /// Arasi or nanatang lets the holder end the round early.
  bool canCallEarlyEnd(int team) {
    final y = scoreYaks(teamPiles[team]!);
    return y.containsKey('arasi') || y.containsKey('nanatang');
  }

  RoundResult endRoundEarly(int team) {
    final y = scoreYaks(teamPiles[team]!);
    final only = y.containsKey('arasi') ? 'arasi' : 'nanatang';
    return RoundResult({team: y[only]!}, team);
  }

  // ---- Scoring ----
  RoundResult scoreRound() {
    final scores = <int, int>{};
    for (final e in teamPiles.entries) {
      scores[e.key] = scoreYaks(e.value).values.fold(0, (a, b) => a + b);
    }
    if (scores.values.every((s) => s == 0)) {
      // No yaks: compare okeiim + teruich totals (equal = tie).
      final pts = {
        for (final e in teamPiles.entries) e.key: e.value.fold<int>(0, (a, c) => a + c.points),
      };
      return RoundResult(scores, _leader(pts));
    }
    return RoundResult(scores, _leader(scores));
  }

  int? _leader(Map<int, int> m) {
    final best = m.values.reduce(max);
    final top = m.entries.where((e) => e.value == best).toList();
    return top.length == 1 ? top.first.key : null;
  }

  /// The losing team deals next round (on a tie, the dealer stays).
  void nextRound(RoundResult r) {
    if (r.winnerTeam == null) return;
    final loser = players.indexWhere((p) => p.team != r.winnerTeam);
    if (loser >= 0) dealer = loser;
  }
}

// ---- Yaks ----
HCard _c(int s, int i) => HCard(s, i);

final Map<String, ({int points, List<HCard> cards})> fixedYaks = {
  'ksaiak': (points: 100, cards: [_c(3, 1), _c(4, 1), _c(6, 1)]),
  'ippai (sakura)': (points: 150, cards: [_c(2, 0), _c(8, 0)]),
  'ippai (buil)': (points: 150, cards: [_c(7, 0), _c(8, 0)]),
  'chauotang': (points: 150, cards: [_c(5, 1), _c(8, 1), _c(9, 1)]),
  'kodangko': (points: 150, cards: [_c(0, 1), _c(1, 1), _c(2, 1)]),
  'nisoro': (points: 200, cards: [_c(10, 0), _c(10, 1), _c(10, 2)]),
  'teppo': (points: 300, cards: [_c(2, 0), _c(7, 0), _c(8, 0)]),
  'inoskasio': (points: 300, cards: [_c(6, 0), _c(9, 0), _c(5, 0)]),
  'chume mats sakura': (points: 300, cards: [_c(0, 0), _c(1, 0), _c(2, 0)]),
  'mats kiri bo': (points: 300, cards: [_c(0, 0), _c(11, 0), _c(7, 0)]),
  'skok': (points: 500, cards: [_c(0, 0), _c(7, 0), _c(11, 0), _c(2, 0)]),
  'kokok': (points: 700, cards: [_c(0, 0), _c(7, 0), _c(11, 0), _c(2, 0), _c(10, 0)]),
  'arasi': (points: 1000, cards: [_c(0, 0), _c(7, 0), _c(11, 0), _c(2, 0), _c(10, 0), _c(1, 0)]),
};

/// Returns every yak found in [pile] with its points. Yaks stack (summed by caller).
Map<String, int> scoreYaks(List<HCard> pile) {
  final have = pile.toSet();
  final out = <String, int>{};
  fixedYaks.forEach((name, y) {
    if (y.cards.every(have.contains)) out[name] = y.points;
  });
  if (pile.where((c) => c.type == CardType.tang).length >= 7) out['nanatang'] = 700;
  if (pile.where((c) => c.type == CardType.teruich).length >= 9) out['toiak'] = 10000;
  return out;
}
