import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:teampilot/pages/workbench/markdown_preview_pane.dart';
import 'package:tp_markdown/tp_markdown.dart';

const _hostKey = Key('markdown-preview-window-host');

class _WindowSizeOverride extends StatefulWidget {
  const _WindowSizeOverride({required this.child, super.key});

  final Widget child;

  @override
  State<_WindowSizeOverride> createState() => _WindowSizeOverrideState();
}

class _WindowSizeOverrideState extends State<_WindowSizeOverride> {
  Size size = const Size(800, 600);

  void setSize(Size next) => setState(() => size = next);

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(size: size),
      child: widget.child,
    );
  }
}

void main() {
  testWidgets(
    'window MediaQuery size change does not rebuild a fixed-width preview pane',
    (tester) async {
      final editing = CodeLineEditingController.fromText('# Hi\n\npreview\n');
      addTearDown(editing.dispose);
      final pane = Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 600,
          child: MarkdownPreviewPane(
            controller: editing,
            resolvers: const MarkdownResolvers(),
            codeBlockMode: ContentDisplayMode.flatten,
            markdownPadding: const EdgeInsets.all(24),
            shellColor: Colors.white,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _WindowSizeOverride(key: _hostKey, child: pane),
          ),
        ),
      );
      await tester.pump();

      var rebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is MarkdownPreviewPane) rebuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      tester
          .state<_WindowSizeOverrideState>(find.byKey(_hostKey))
          .setSize(const Size(1400, 900));
      await tester.pump();

      expect(
        rebuilds,
        0,
        reason:
            'preview tokens must use pane constraints, not MediaQuery.sizeOf',
      );
    },
  );
}
