// Run with: dart test   (add `test` to dev_dependencies in pubspec.yaml)
import 'dart:math';
import 'package:test/test.dart';
import 'hanahuda_engine.dart';

HCard c(int s, int i) => HCard(s, i);

void main() {
  group('deck', () {
    final deck = fullDeck();
    int count(CardType t) => deck.where((x) => x.type == t).length;
    test('48 cards', () => expect(deck.length, 48));
    test('6 okeiim', () => expect(count(CardType.okeiim), 6));
    test('10 tang', () => expect(count(CardType.tang), 10));
    test('9 teruich', () => expect(count(CardType.teruich), 9));
    test('23 kas', () => expect(count(CardType.kas), 23));
    test('buil and kiri have no tang', () {
      expect(deck.where((x) => (x.set == 7 || x.set == 11) && x.type == CardType.tang), isEmpty);
    });
    test('nisoro has exactly one kas', () {
      expect(deck.where((x) => x.set == 10 && x.type == CardType.kas).length, 1);
    });
  });

  group('deal', () {
    for (final n in [2, 3, 4]) {
      test('$n players', () {
        final g = Game([for (var i = 0; i < n; i++) Player('p$i', n == 4 ? i % 2 : i)]);
        g.deal(rng: Random(1));
        final h = Game.handSize(n);
        expect(g.players.every((p) => p.hand.length == h), isTrue);
        expect(g.table.length, h);
        expect(g.players.expand((p) => p.hand).length + g.table.length + g.stack.length, 48);
        expect(g.current, 1); // left of dealer 0
      });
    }
  });

  group('yaks', () {
    int pts(List<HCard> p, String yak) => scoreYaks(p)[yak] ?? 0;
    test('ksaiak', () => expect(pts([c(3, 1), c(4, 1), c(6, 1)], 'ksaiak'), 100));
    test('chauotang', () => expect(pts([c(5, 1), c(8, 1), c(9, 1)], 'chauotang'), 150));
    test('kodangko', () => expect(pts([c(0, 1), c(1, 1), c(2, 1)], 'kodangko'), 150));
    test('ippai sakura', () => expect(pts([c(2, 0), c(8, 0)], 'ippai (sakura)'), 150));
    test('ippai buil', () => expect(pts([c(7, 0), c(8, 0)], 'ippai (buil)'), 150));
    test('teppo', () => expect(pts([c(2, 0), c(7, 0), c(8, 0)], 'teppo'), 300));
    test('nisoro', () => expect(pts([c(10, 0), c(10, 1), c(10, 2)], 'nisoro'), 200));
    test('inoskasio', () => expect(pts([c(6, 0), c(9, 0), c(5, 0)], 'inoskasio'), 300));
    test('chume mats sakura', () => expect(pts([c(0, 0), c(1, 0), c(2, 0)], 'chume mats sakura'), 300));
    test('mats kiri bo', () => expect(pts([c(0, 0), c(11, 0), c(7, 0)], 'mats kiri bo'), 300));
    test('skok / kokok / arasi', () {
      final four = [c(0, 0), c(7, 0), c(11, 0), c(2, 0)];
      expect(pts(four, 'skok'), 500);
      expect(pts([...four, c(10, 0)], 'kokok'), 700);
      expect(pts([...four, c(10, 0), c(1, 0)], 'arasi'), 1000);
    });
    test('nanatang needs any 7 tang', () {
      final tang = fullDeck().where((x) => x.type == CardType.tang).toList();
      expect(pts(tang.sublist(0, 6), 'nanatang'), 0);
      expect(pts(tang.sublist(0, 7), 'nanatang'), 700);
    });
    test('toiak needs all 9 teruich', () {
      final t = fullDeck().where((x) => x.type == CardType.teruich).toList();
      expect(pts(t.sublist(0, 8), 'toiak'), 0);
      expect(pts(t, 'toiak'), 10000);
    });
    test('yaks stack', () {
      final pile = [c(3, 1), c(4, 1), c(6, 1), c(0, 1), c(1, 1), c(2, 1)];
      final total = scoreYaks(pile).values.fold(0, (a, b) => a + b);
      expect(total, 250); // ksaiak 100 + kodangko 150
    });
  });

  group('turn rules', () {
    Game fresh() {
      final g = Game([Player('a', 0), Player('b', 1)]);
      g.table.clear();
      g.stack.clear();
      for (final p in g.players) {
        p.hand.clear();
      }
      return g;
    }

    test('forced capture limits legal plays', () {
      final g = fresh()..current = 0;
      g.table.add(c(0, 2));
      g.players[0].hand.addAll([c(0, 3), c(5, 2)]);
      expect(g.legalPlays(g.players[0]), [c(0, 3)]);
    });
    test('no match: any card may be played and goes to table', () {
      final g = fresh()..current = 0;
      g.table.add(c(1, 2));
      g.players[0].hand.addAll([c(0, 3), c(5, 2)]);
      expect(g.legalPlays(g.players[0]).length, 2);
      g.playFromHand(c(5, 2));
      expect(g.table.contains(c(5, 2)), isTrue);
    });
    test('capture takes one matching card plus played card', () {
      final g = fresh()..current = 0;
      g.table.addAll([c(0, 0), c(0, 2)]);
      g.players[0].hand.add(c(0, 3));
      g.playFromHand(c(0, 3), capture: c(0, 0));
      expect(g.teamPiles[0], containsAll([c(0, 3), c(0, 0)]));
      expect(g.table, [c(0, 2)]);
    });
    test('capture required when match exists', () {
      final g = fresh()..current = 0;
      g.table.add(c(0, 0));
      g.players[0].hand.add(c(0, 3));
      expect(() => g.playFromHand(c(0, 3)), throwsStateError);
    });
    test('omkais captures matching flip', () {
      final g = fresh()..current = 0;
      g.table.add(c(4, 0));
      g.stack.add(c(4, 2));
      g.omkais();
      g.resolveDraw(capture: c(4, 0));
      expect(g.teamPiles[0], containsAll([c(4, 2), c(4, 0)]));
    });
    test('chitsiobiki detected', () {
      final g = fresh();
      g.players[0].hand.addAll([c(2, 0), c(2, 1), c(2, 2), c(5, 0)]);
      expect(g.chitsiobikiSets(g.players[0]), [2]);
    });
  });

  group('round end', () {
    test('no yaks: higher okeiim+teruich total wins, equal is tie', () {
      final g = Game([Player('a', 0), Player('b', 1)]);
      g.teamPiles[0]!.add(c(0, 0)); // 50
      g.teamPiles[1]!.add(c(3, 0)); // 10
      expect(g.scoreRound().winnerTeam, 0);
      g.teamPiles[1]!.clear();
      g.teamPiles[1]!.add(c(1, 0)); // 50
      expect(g.scoreRound().winnerTeam, isNull);
    });
    test('arasi allows early end and scores only that yak', () {
      final g = Game([Player('a', 0), Player('b', 1)]);
      g.teamPiles[0]!.addAll([c(0, 0), c(7, 0), c(11, 0), c(2, 0), c(10, 0), c(1, 0), c(3, 1), c(4, 1), c(6, 1)]);
      expect(g.canCallEarlyEnd(0), isTrue);
      final r = g.endRoundEarly(0);
      expect(r.yakScores, {0: 1000});
    });
  });
}
