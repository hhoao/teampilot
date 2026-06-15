import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/diff/line_pairing.dart';

void main() {
  group('pairChangeBlock', () {
    test('empty deletes -> all inserts', () {
      final ops = pairChangeBlock(const [], const ['a', 'b']);
      expect(ops.map((o) => o.kind),
          everyElement(PairOpKind.insert));
      expect(ops.map((o) => o.rightIndex), [0, 1]);
    });

    test('empty inserts -> all deletes', () {
      final ops = pairChangeBlock(const ['a', 'b'], const []);
      expect(ops.map((o) => o.kind),
          everyElement(PairOpKind.delete));
      expect(ops.map((o) => o.leftIndex), [0, 1]);
    });

    test('similar lines pair as a single modify', () {
      final ops = pairChangeBlock(
        const ['final foo = 1;'],
        const ['final foo = 2;'],
      );
      expect(ops.length, 1);
      expect(ops.single.kind, PairOpKind.modify);
      expect(ops.single.similarity, greaterThan(0.5));
    });

    test('dissimilar lines become delete + insert, not a modify', () {
      final ops = pairChangeBlock(
        const ['import "package:a/a.dart";'],
        const ['return widget.build(context);'],
      );
      expect(ops.any((o) => o.kind == PairOpKind.modify), isFalse);
      expect(ops.where((o) => o.kind == PairOpKind.delete).length, 1);
      expect(ops.where((o) => o.kind == PairOpKind.insert).length, 1);
    });

    test('pairs the most similar line, not the positional one', () {
      // The edited "bravo" line is second; index-order pairing would wrongly
      // pair it with the inserted line. Similarity pairing must match bravo↔bravo.
      final dels = ['bravo line one'];
      final ins = ['brand new line', 'bravo line two'];
      final ops = pairChangeBlock(dels, ins);

      final modify = ops.firstWhere((o) => o.kind == PairOpKind.modify);
      expect(modify.leftIndex, 0);
      expect(modify.rightIndex, 1); // matched bravo↔bravo, not index 0
      // The unrelated insert remains an insert.
      expect(ops.where((o) => o.kind == PairOpKind.insert).single.rightIndex, 0);
    });

    test('alignment is monotonic (no crossing pairs)', () {
      final dels = ['alpha 1', 'beta 1', 'gamma 1'];
      final ins = ['alpha 2', 'beta 2', 'gamma 2'];
      final ops = pairChangeBlock(dels, ins);

      final modifies = ops.where((o) => o.kind == PairOpKind.modify).toList();
      expect(modifies.length, 3);
      var lastLeft = -1;
      var lastRight = -1;
      for (final op in modifies) {
        expect(op.leftIndex, greaterThan(lastLeft));
        expect(op.rightIndex, greaterThan(lastRight));
        lastLeft = op.leftIndex;
        lastRight = op.rightIndex;
      }
    });

    test('threshold gates whether a pair is a modify', () {
      // ~50% similar; a high threshold should reject the modify.
      final dels = ['abcd'];
      final ins = ['abef'];
      final lenient = pairChangeBlock(dels, ins, threshold: 0.4);
      expect(lenient.single.kind, PairOpKind.modify);

      final strict = pairChangeBlock(dels, ins, threshold: 0.9);
      expect(strict.any((o) => o.kind == PairOpKind.modify), isFalse);
    });

    test('oversized block skips similarity pairing (bounded cost)', () {
      // A large contiguous modify block. The full O(n·m·L²) similarity matrix
      // would take seconds and freeze the UI; the cap must short-circuit it to
      // plain delete+insert and stay near-instant.
      const n = 400;
      final dels = [
        for (var i = 0; i < n; i++) 'final value$i = compute(x$i, y$i, a);',
      ];
      final ins = [
        for (var i = 0; i < n; i++) 'final value$i = compute(x$i, y$i, B);',
      ];

      final sw = Stopwatch()..start();
      final ops = pairChangeBlock(dels, ins);
      sw.stop();

      expect(ops.any((o) => o.kind == PairOpKind.modify), isFalse,
          reason: 'oversized blocks must not build the similarity matrix');
      expect(ops.where((o) => o.kind == PairOpKind.delete).length, n);
      expect(ops.where((o) => o.kind == PairOpKind.insert).length, n);
      expect(sw.elapsedMilliseconds, lessThan(100),
          reason: 'must avoid the quadratic similarity matrix');
    });

    test('very long lines skip similarity pairing even with few lines', () {
      // Few lines but each enormous: the per-cell char-LCS is O(L²), so the
      // character budget (not just the cell count) must trigger the fallback.
      final longA = List.filled(60000, 'a').join();
      final longB = '${longA}b';

      final sw = Stopwatch()..start();
      final ops = pairChangeBlock([longA, longA], [longB, longB]);
      sw.stop();

      expect(ops.any((o) => o.kind == PairOpKind.modify), isFalse);
      expect(sw.elapsedMilliseconds, lessThan(100));
    });

    test('one huge changed line skips similarity pairing', () {
      // A single line each side (cell count = 1) but each ~20k chars. The cost
      // of one similarity cell is O(La·Lb), so the work budget — not the cell
      // count or the total char count — must trigger the fallback.
      final a = List.filled(20000, 'a').join();
      final b = '${List.filled(20000, 'a').join()}b';

      final sw = Stopwatch()..start();
      final ops = pairChangeBlock([a], [b]);
      sw.stop();

      expect(ops.any((o) => o.kind == PairOpKind.modify), isFalse);
      expect(ops.map((o) => o.kind),
          [PairOpKind.delete, PairOpKind.insert]);
      expect(sw.elapsedMilliseconds, lessThan(100));
    });

    test('blocks within the cap still pair as modifies', () {
      // A 40×40 block is under the cap, so similarity pairing still applies.
      const n = 40;
      final dels = [for (var i = 0; i < n; i++) 'final value$i = compute(a);'];
      final ins = [for (var i = 0; i < n; i++) 'final value$i = compute(b);'];
      final ops = pairChangeBlock(dels, ins);
      expect(ops.where((o) => o.kind == PairOpKind.modify).length, n);
    });
  });
}
