import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/terminal/file_path_link_provider.dart';

class _NeverFs implements Filesystem {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  late FilePathLinkProvider p;
  setUp(() => p = FilePathLinkProvider(fs: _NeverFs(), launchCwd: '/proj'));

  List<String> payloads(String line) => p.scan(line).map((s) => s.payload).toList();

  test('detects relative, dotted, absolute, and windows paths', () {
    expect(payloads('Read(client/lib/foo.dart)'), contains('client/lib/foo.dart'));
    expect(payloads('see ./README.md now'), contains('./README.md'));
    expect(payloads('open ../a/b.txt'), contains('../a/b.txt'));
    expect(payloads('at /etc/hosts here'), contains('/etc/hosts'));
  });

  test('keeps :line[:col] suffix in the payload', () {
    expect(payloads('Update(lib/main.dart:42)'), contains('lib/main.dart:42'));
    expect(payloads('err at src/x.dart:10:5 here'), contains('src/x.dart:10:5'));
  });

  test('rejects non-paths', () {
    expect(payloads('version 1.2.3 shipped'), isEmpty);
    expect(payloads('just plain english words'), isEmpty);
  });

  test('span ranges align with the matched substring', () {
    final line = 'Read(client/lib/foo.dart)';
    final span = p.scan(line).firstWhere((s) => s.payload == 'client/lib/foo.dart');
    expect(line.substring(span.start, span.end), 'client/lib/foo.dart');
  });

  test('isEnabled is false in Task 8 (validation added later)', () {
    final span = p.scan('Read(lib/a.dart)').first;
    expect(p.isEnabled(span), isFalse);
  });
}
