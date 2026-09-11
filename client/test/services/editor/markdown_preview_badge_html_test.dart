import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/markdown_preview_link_handler.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  testWidgets('HTML badge div routes http imgs to the widget layer', (
    tester,
  ) async {
    const source = '''
<div align="center">
  <a href="https://github.com/hhoao/huji/releases"><img src="https://img.shields.io/github/v/release/hhoao/huji?logo=github&label=Release" alt="Release"></a>
  <a href="https://github.com/hhoao/huji/stargazers"><img src="https://img.shields.io/github/stars/hhoao/huji?logo=github&label=Stars" alt="Stars"></a>
</div>
''';
    final doc = compileMarkdown(source);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: VirtualMarkdownView(
            document: doc,
            tokens: MarkdownTokens.test(),
            resolvers: MarkdownResolvers(
              buildImageWidget: (src, {required inline, required inlineHeight}) =>
                  buildMarkdownPreviewImage(
                src: src,
                markdownFilePath: '/repo/README.md',
                workspaceRoots: const ['/repo'],
                inline: inline,
                inlineHeight: inlineHeight,
              ),
              resolveImage: (src) => resolveMarkdownPreviewImage(
                src: src,
                markdownFilePath: '/repo/README.md',
                workspaceRoots: const ['/repo'],
              ),
            ),
            flatten: true,
          ),
        ),
      ),
    ));
    await tester.pump();

    // Both imgs are claimed by the widget hook (no NetworkImage → no
    // "Invalid image data"), even though neither URL has a .svg extension.
    final imageWidgets = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(
      imageWidgets.where((i) => i.image is NetworkImage),
      isEmpty,
      reason: 'http imgs must not fall to NetworkImage',
    );
    expect(tester.takeException(), isNull);
  });
}
