import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/workbench/workspace_href_classifier.dart';

void main() {
  const classifier = WorkspaceHrefClassifier();

  test('http(s) with host is external', () {
    final httpKind = classifier.classify('https://example.com/a');
    expect(httpKind, isA<WorkspaceHrefExternal>());
    expect((httpKind as WorkspaceHrefExternal).uri.host, 'example.com');

    final insecure = classifier.classify('http://example.com');
    expect(insecure, isA<WorkspaceHrefExternal>());
  });

  test('file:// is a local host path', () {
    final kind = classifier.classify('file:///tmp/notes.md');
    expect(kind, isA<WorkspaceHrefLocalPath>());
    expect(
      (kind as WorkspaceHrefLocalPath).rawPath,
      Uri.parse('file:///tmp/notes.md').toFilePath(),
    );
  });

  test('relative path strips fragment', () {
    final kind = classifier.classify('src/foo.dart#heading');
    expect(kind, isA<WorkspaceHrefLocalPath>());
    expect((kind as WorkspaceHrefLocalPath).rawPath, 'src/foo.dart');
  });

  test('hash-only, mailto, empty, and unknown schemes are ignored', () {
    expect(classifier.classify(''), isA<WorkspaceHrefIgnored>());
    expect(classifier.classify('   '), isA<WorkspaceHrefIgnored>());
    expect(classifier.classify('#heading'), isA<WorkspaceHrefIgnored>());
    expect(classifier.classify('mailto:a@b.com'), isA<WorkspaceHrefIgnored>());
    expect(
      classifier.classify('javascript:alert(1)'),
      isA<WorkspaceHrefIgnored>(),
    );
  });
}
