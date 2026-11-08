// Simple computer opponent for Palauan Hanahuda.
// Greedy 1-ply strategy: value captures, build toward yaks, deny opponents.
import 'hanahuda_engine.dart';

double cardValue(HCard c) {
  switch (c.type) {
    case CardType.okeiim:
      return 50;
    case CardType.tang:
      return 20;
    case CardType.teruich:
      return 12;
    case CardType.kas:
      return 2;
  }
}

/// How close a pile is to completing yaks (completed = full points).
double _progress(List<HCard> pile) {
  final have = pile.toSet();
  var s = 0.0;
  fixedYaks.forEach((_, y) {
    final owned = y.cards.where(have.contains).length;
    final r = owned / y.cards.length;
    s += y.points * r * r;
  });
  final tang = pile.where((c) => c.type == CardType.tang).length;
  final r = (tang > 7 ? 7 : tang) / 7;
  s += 700 * r * r;
  return s;
}

double _gain(List<HCard> pile, List<HCard> add) =>
    _progress([...pile, ...add]) - _progress(pile);

class Move {
  final HCard card;
  final HCard? capture;
  final double score;
  Move(this.card, this.capture, this.score);
}

class HanahudaAI {
  /// Score taking [capture] (plus [played], if any) for the current team.
  double _scoreCapture(Game g, HCard capture, {HCard? played}) {
    final me = g.currentPlayer.team;
    final mine = [...g.stackOf(capture.set), if (played != null) played];
    var s = _gain(g.teamPiles[me]!, mine) + mine.fold(0.0, (a, c) => a + cardValue(c));
    // Denial: value of this card to opponents if left on the table.
    for (final e in g.teamPiles.entries) {
      if (e.key != me) s += 0.5 * _gain(e.value, [capture]);
    }
    return s;
  }

  /// Score leaving [card] on the table (no capture available).
  double _scoreDiscard(Game g, HCard card) {
    final me = g.currentPlayer.team;
    var risk = cardValue(card);
    for (final e in g.teamPiles.entries) {
      if (e.key != me) risk += 0.5 * _gain(e.value, [card]);
    }
    return -risk;
  }

  Move chooseMove(Game g) {
    Move? best;
    for (final card in g.legalPlays(g.currentPlayer)) {
      final opts = g.captureOptions(card);
      if (opts.isEmpty) {
        final m = Move(card, null, _scoreDiscard(g, card));
        if (best == null || m.score > best.score) best = m;
      } else {
        for (final cap in opts) {
          final m = Move(card, cap, _scoreCapture(g, cap, played: card));
          if (best == null || m.score > best.score) best = m;
        }
      }
    }
    return best!;
  }

  /// Pick which table card to capture with the flipped [drawn] card.
  HCard? chooseDrawCapture(Game g, HCard drawn) {
    final opts = g.captureOptions(drawn);
    if (opts.isEmpty) return null;
    opts.sort((a, b) => _scoreCapture(g, b, played: drawn)
        .compareTo(_scoreCapture(g, a, played: drawn)));
    return opts.first;
  }

  /// Which card to trade away for chitsiobiki (lowest value in that set).
  HCard? chitsiobikiGive(Game g, Player p) {
    final sets = g.chitsiobikiSets(p);
    if (sets.isEmpty) return null;
    final cards = p.hand.where((c) => c.set == sets.first).toList()
      ..sort((a, b) => cardValue(a).compareTo(cardValue(b)));
    return cards.first;
  }

  /// Call arasi/nanatang early when the called yak is most of what we hold.
  bool shouldCallEarlyEnd(Game g) {
    final team = g.currentPlayer.team;
    if (!g.canCallEarlyEnd(team)) return false;
    final yaks = scoreYaks(g.teamPiles[team]!);
    if (yaks.containsKey('arasi')) return true;
    final total = yaks.values.fold(0, (a, b) => a + b);
    return yaks['nanatang']! >= 0.6 * total;
  }

  /// Plays one full turn. Returns a result if the round ended early.
  RoundResult? playTurn(Game g) {
    final m = chooseMove(g);
    g.playFromHand(m.card, capture: m.capture);
    final drawn = g.omkais();
    if (drawn != null) g.resolveDraw(capture: chooseDrawCapture(g, drawn));
    if (shouldCallEarlyEnd(g)) return g.endRoundEarly(g.currentPlayer.team);
    g.endTurn();
    return null;
  }
}

/// Plays a whole round between AIs (useful for testing and simulation).
RoundResult simulateRound(Game g, HanahudaAI ai) {
  while (!g.roundOver) {
    final early = ai.playTurn(g);
    if (early != null) return early;
  }
  return g.scoreRound();
}
