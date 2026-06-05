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
  });
}
