import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/terminal/file_path_link_provider.dart';
import 'package:teampilot/services/terminal/terminal_uri_opener.dart';

import '../../support/in_memory_filesystem.dart';

class _NeverFs implements Filesystem {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// Returns the absolute path that [TerminalUriOpener.resolveLocalFilePath]
/// would produce for [relative] when the cwd is [cwd].
/// This is platform-sensitive (backslashes on Windows).
String _resolved(String relative, {String cwd = '/proj'}) =>
    TerminalUriOpener.resolveLocalFilePath(relative, workingDirectory: cwd)!;

/// An [InMemoryFilesystem] with platform-correct path keys for test files.
/// Registers [relative] paths resolved against [cwd] using the same logic
/// that [FilePathLinkProvider] uses, so stat lookups always match.
InMemoryFilesystem _fsWithFiles(
  List<String> relativePaths, {
  String cwd = '/proj',
}) {
  final fs = InMemoryFilesystem(
    pathContext: p.Context(
      style: Platform.isWindows ? p.Style.windows : p.Style.posix,
    ),
  );
  for (final rel in relativePaths) {
    final abs = _resolved(rel, cwd: cwd);
    fs.files[abs] = '';
  }
  return fs;
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

  test('isEnabled is false before async validation settles', () {
    // Synchronous check: _NeverFs throws UnimplementedError (caught in _validate),
    // so no confirmation happens before the event loop runs.
    final span = p.scan('Read(lib/a.dart)').first;
    expect(p.isEnabled(span), isFalse);
  });

  // ---- Task 9: async filesystem validation tests ----

  test('candidate becomes enabled after fs confirms existence, and notifies',
      () async {
    final fs = _fsWithFiles(['client/lib/foo.dart']);
    final provider = FilePathLinkProvider(fs: fs, launchCwd: '/proj');

    final span = provider
        .scan('Read(client/lib/foo.dart)')
        .firstWhere((s) => s.payload == 'client/lib/foo.dart');
    expect(provider.isEnabled(span), isFalse); // not validated yet

    var notified = 0;
    provider.addListener(() => notified++);

    // scan triggers fire-and-forget validation
    provider.scan('Read(client/lib/foo.dart)').toList();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(notified, greaterThan(0));
    expect(provider.isEnabled(span), isTrue);
  });

  test('non-existent path never enables', () async {
    final fs = _fsWithFiles([]); // no files registered
    final provider = FilePathLinkProvider(fs: fs, launchCwd: '/proj');

    final span = provider.scan('Read(nope/x.dart)').first;
    provider.scan('Read(nope/x.dart)').toList();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(provider.isEnabled(span), isFalse);
  });

  test('a path with :line suffix validates against the stripped file path',
      () async {
    final fs = _fsWithFiles(['lib/main.dart']);
    final provider = FilePathLinkProvider(fs: fs, launchCwd: '/proj');

    final span = provider
        .scan('Update(lib/main.dart:42)')
        .firstWhere((s) => s.payload.endsWith(':42'));
    provider.scan('Update(lib/main.dart:42)').toList();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(provider.isEnabled(span), isTrue,
        reason: 'suffix stripped before stat; payload keeps :42');
    expect(span.payload, 'lib/main.dart:42');
  });

  test('directory is not a clickable file', () async {
    // Register the resolved path as a real DIRECTORY so validation actually
    // exercises the `stat.isFile` guard (an existing dir must NOT enable).
    final fs = _fsWithFiles([]);
    fs.directories.add(_resolved('lib/widgets.dart'));
    final provider = FilePathLinkProvider(fs: fs, launchCwd: '/proj');

    final span = provider
        .scan('see lib/widgets.dart here')
        .firstWhere((s) => s.payload == 'lib/widgets.dart');
    provider.scan('see lib/widgets.dart here').toList();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(provider.isEnabled(span), isFalse,
        reason: 'an existing directory must not be a clickable file');
  });
}
