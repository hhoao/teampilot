import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/diff/diff_model.dart';
import 'package:teampilot/services/diff/unified_diff_parser.dart';

void main() {
  group('parseUnifiedDiff', () {
    test('empty input yields no files', () {
      expect(parseUnifiedDiff(''), isEmpty);
      expect(parseUnifiedDiff('   \n  '), isEmpty);
    });

    test('parses a single-hunk modification with correct line numbers', () {
      const diff = '''
diff --git a/lib/foo.dart b/lib/foo.dart
index 680d11d..e38878e 100644
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -10,4 +10,5 @@ class Foo {
   final int a;
-  final int b;
+  final int bee;
+  final int c;
   final int d;
''';
      final files = parseUnifiedDiff(diff);
      expect(files.length, 1);
      final file = files.single;
      expect(file.oldPath, 'lib/foo.dart');
      expect(file.newPath, 'lib/foo.dart');
      expect(file.hunks.single.oldStart, 10);
      expect(file.hunks.single.newStart, 10);

      // Context row keeps its hunk-derived line numbers.
      final firstEqual = file.rows.first;
      expect(firstEqual.kind, DiffRowKind.equal);
      expect(firstEqual.leftLineNo, 10);
      expect(firstEqual.rightLineNo, 10);

      // 'final int b;' -> 'final int bee;' is similar => modify with inline.
      final modify = file.rows.firstWhere((r) => r.kind == DiffRowKind.modify);
      expect(modify.leftText, '  final int b;');
      expect(modify.rightText, '  final int bee;');
      expect(modify.rightInline, isNotEmpty);

      // 'final int c;' is a genuine insertion.
      expect(file.rows.any((r) =>
          r.kind == DiffRowKind.insert && r.rightText == '  final int c;'),
          isTrue);
    });

    test('handles new and deleted files via /dev/null', () {
      const added = '''
diff --git a/new.txt b/new.txt
new file mode 100644
--- /dev/null
+++ b/new.txt
@@ -0,0 +1,2 @@
+hello
+world
''';
      final file = parseUnifiedDiff(added).single;
      expect(file.isNew, isTrue);
      expect(file.oldPath, isNull);
      expect(file.newPath, 'new.txt');
      expect(file.rows.where((r) => r.kind == DiffRowKind.insert).length, 2);

      const deleted = '''
diff --git a/gone.txt b/gone.txt
deleted file mode 100644
--- a/gone.txt
+++ /dev/null
@@ -1,1 +0,0 @@
-bye
''';
      final del = parseUnifiedDiff(deleted).single;
      expect(del.isDeleted, isTrue);
      expect(del.newPath, isNull);
      expect(del.rows.single.kind, DiffRowKind.delete);
    });

    test('detects binary files', () {
      const diff = '''
diff --git a/img.png b/img.png
index abc..def 100644
Binary files a/img.png and b/img.png differ
''';
      final file = parseUnifiedDiff(diff).single;
      expect(file.isBinary, isTrue);
      expect(file.rows, isEmpty);
    });

    test('parses multiple files and multiple hunks', () {
      const diff = '''
diff --git a/one.dart b/one.dart
--- a/one.dart
+++ b/one.dart
@@ -1,2 +1,2 @@
-a
+A
 b
@@ -10,2 +10,2 @@
-c
+C
 d
diff --git a/two.dart b/two.dart
--- a/two.dart
+++ b/two.dart
@@ -5,1 +5,1 @@
-x
+y
''';
      final files = parseUnifiedDiff(diff);
      expect(files.length, 2);
      expect(files[0].hunks.length, 2);
      // Second hunk starts at old/new line 10.
      expect(files[0].hunks[1].oldStart, 10);
      // Second hunk's rows continue from where the first hunk ended.
      expect(files[0].hunks[1].rowIndex, greaterThan(0));
      expect(files[1].displayPath, 'two.dart');
    });

    test('hunk header without explicit counts defaults to 1', () {
      const diff = '''
--- a/f
+++ b/f
@@ -3 +3 @@
-value old
+value new
''';
      final file = parseUnifiedDiff(diff).single;
      expect(file.hunks.single.oldStart, 3);
      // Similar lines pair into one modify row anchored at line 3.
      expect(file.rows.single.kind, DiffRowKind.modify);
      expect(file.rows.single.leftLineNo, 3);
    });

    test('ignores "no newline at end of file" markers', () {
      const diff = '''
--- a/f
+++ b/f
@@ -1,1 +1,1 @@
-value old
\\ No newline at end of file
+value new
\\ No newline at end of file
''';
      final file = parseUnifiedDiff(diff).single;
      expect(file.rows.single.kind, DiffRowKind.modify);
      // The marker text must not leak into any row.
      expect(
        file.rows.every((r) =>
            !(r.leftText ?? '').contains('No newline') &&
            !(r.rightText ?? '').contains('No newline')),
        isTrue,
      );
    });

    test('parseUnifiedDiffToResult flattens files into one result', () {
      const diff = '''
diff --git a/one.dart b/one.dart
--- a/one.dart
+++ b/one.dart
@@ -1,2 +1,2 @@
-a
+A
 b
diff --git a/two.dart b/two.dart
--- a/two.dart
+++ b/two.dart
@@ -1,1 +1,1 @@
-x
+y
''';
      final result = parseUnifiedDiffToResult(diff);
      expect(result.rows, isNotEmpty);
      // Two separate change regions across the two files.
      expect(result.blocks.length, 2);
    });

    test('parseUnifiedDiffToResult is empty for an empty diff', () {
      expect(parseUnifiedDiffToResult('').rows, isEmpty);
      expect(parseUnifiedDiffToResult('').hasChanges, isFalse);
    });

    test('computes change blocks for navigation', () {
      const diff = '''
--- a/f
+++ b/f
@@ -1,5 +1,5 @@
 a
-b
+B
 c
-d
+D
 e
''';
      final file = parseUnifiedDiff(diff).single;
      // Two separate modify regions separated by a context line.
      expect(file.blocks.length, 2);
    });
  });
}
