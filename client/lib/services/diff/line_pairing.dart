/// Similarity-based pairing of deleted/inserted lines within a single change
/// block, so that "a line was edited" renders as one modify row instead of a
/// delete row plus an unrelated insert row.
///
/// Pure functions, no Flutter dependency.
library;

import 'diff_options.dart';

/// What a [PairOp] represents within an aligned change block.
enum PairOpKind { modify, delete, insert }

/// One step of the monotonic alignment between deleted and inserted lines.
class PairOp {
  const PairOp({
    required this.kind,
    this.leftIndex = -1,
    this.rightIndex = -1,
    this.similarity = 0,
  });

  final PairOpKind kind;

  /// Index into the deleted-lines list (-1 for an insert op).
  final int leftIndex;

  /// Index into the inserted-lines list (-1 for a delete op).
  final int rightIndex;

  /// Similarity score [0, 1] for modify ops; 0 otherwise.
  final double similarity;

  @override
  bool operator ==(Object other) =>
      other is PairOp &&
      other.kind == kind &&
      other.leftIndex == leftIndex &&
      other.rightIndex == rightIndex;

  @override
  int get hashCode => Object.hash(kind, leftIndex, rightIndex);

  @override
  String toString() =>
      'PairOp(${kind.name}, L$leftIndex R$rightIndex)';
}

/// Aligns [dels] against [ins] preserving order, matching a deleted line to an
/// inserted line as a modify only when their similarity reaches [threshold].
///
/// Uses Needleman–Wunsch-style DP maximizing the total similarity of matched
/// pairs; unmatched lines become delete/insert ops. Change blocks are small so
/// the O(n·m) table is cheap.
List<PairOp> pairChangeBlock(
  List<String> dels,
  List<String> ins, {
  double threshold = 0.5,
  DiffOptions options = DiffOptions.none,
}) {
  final n = dels.length;
  final m = ins.length;
  if (n == 0) {
    return [for (var j = 0; j < m; j++) PairOp(kind: PairOpKind.insert, rightIndex: j)];
  }
  if (m == 0) {
    return [for (var i = 0; i < n; i++) PairOp(kind: PairOpKind.delete, leftIndex: i)];
  }

  final sim = List.generate(
    n,
    (i) => List.generate(
      m,
      (j) => _similarity(options.normalize(dels[i]), options.normalize(ins[j])),
    ),
  );

  // f[i][j] = best total match-score aligning dels[i..] with ins[j..].
  final f = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
  // 0 = modify, 1 = delete, 2 = insert.
  final choice = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var j = m - 1; j >= 0; j--) {
    choice[n][j] = 2;
  }
  for (var i = n - 1; i >= 0; i--) {
    choice[i][m] = 1;
  }
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      final matchScore = sim[i][j] >= threshold
          ? sim[i][j] + f[i + 1][j + 1]
          : double.negativeInfinity;
      final delScore = f[i + 1][j];
      final insScore = f[i][j + 1];
      if (matchScore != double.negativeInfinity &&
          matchScore >= delScore &&
          matchScore >= insScore) {
        f[i][j] = matchScore;
        choice[i][j] = 0;
      } else if (delScore >= insScore) {
        f[i][j] = delScore;
        choice[i][j] = 1;
      } else {
        f[i][j] = insScore;
        choice[i][j] = 2;
      }
    }
  }

  final ops = <PairOp>[];
  var i = 0;
  var j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && choice[i][j] == 0) {
      ops.add(PairOp(
        kind: PairOpKind.modify,
        leftIndex: i,
        rightIndex: j,
        similarity: sim[i][j],
      ));
      i++;
      j++;
    } else if (i < n && (j >= m || choice[i][j] == 1)) {
      ops.add(PairOp(kind: PairOpKind.delete, leftIndex: i));
      i++;
    } else {
      ops.add(PairOp(kind: PairOpKind.insert, rightIndex: j));
      j++;
    }
  }
  return ops;
}

/// Character-LCS similarity in [0, 1]: `2·lcs / (len(a) + len(b))`.
double _similarity(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  final x = a.codeUnits;
  final y = b.codeUnits;
  final n = x.length;
  final m = y.length;
  var prev = List<int>.filled(m + 1, 0);
  var cur = List<int>.filled(m + 1, 0);
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      if (x[i - 1] == y[j - 1]) {
        cur[j] = prev[j - 1] + 1;
      } else {
        cur[j] = prev[j] > cur[j - 1] ? prev[j] : cur[j - 1];
      }
    }
    final tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return 2.0 * prev[m] / (n + m);
}
