import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  testWidgets('scope defaults are foldFixedHeight and propagate modes', (
    tester,
  ) async {
    String? readUser;
    String? readCode;
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownDisplayModeScope(
          userMessageMode: ContentDisplayMode.flatten,
          codeBlockMode: ContentDisplayMode.foldExpandFull,
          child: Builder(
            builder: (context) {
              readUser = MarkdownDisplayModeScope.userMessageOf(context).name;
              readCode = MarkdownDisplayModeScope.codeBlockOf(context).name;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(readUser, 'flatten');
    expect(readCode, 'foldExpandFull');
  });

  testWidgets('absent scope falls back to foldFixedHeight', (tester) async {
    String? user;
    String? code;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            user = MarkdownDisplayModeScope.userMessageOf(context).name;
            code = MarkdownDisplayModeScope.codeBlockOf(context).name;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(user, 'foldFixedHeight');
    expect(code, 'foldFixedHeight');
  });
}
