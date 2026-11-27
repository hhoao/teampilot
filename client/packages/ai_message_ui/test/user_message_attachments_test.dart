import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File image;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('teampilot-chat-image-');
    image = File('${directory.path}/preview.png');
    await image.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Widget harness(
    String text, {
    bool editing = false,
    ValueChanged<AiUserMessageImage>? onOpen,
  }) {
    return MaterialApp(
      theme: ThemeData(
        extensions: [
          AiMessageTheme.test(userBubbleColor: Colors.blue.shade100),
        ],
      ),
      home: Scaffold(
        body: AiMessageView(
          message: AiMessage(
            id: 'u1',
            role: AiRole.user,
            parts: [AiTextPart(text: text)],
          ),
          userAttachmentWorkspaceRoot: directory.path,
          userAttachmentUsesPosixPaths: true,
          onOpenUserImage: onOpen,
          showActionBar: false,
          editing: editing,
          onCancelEdit: () {},
        ),
      ),
    );
  }

  test('parses relative image references without changing copy text', () {
    final content = parseAiUserMessageImages(
      '请看 @preview.png 这张图片',
      workspaceRoot: directory.path,
      usesPosixPaths: true,
    );

    expect(content.images, hasLength(1));
    expect(content.images.single.path, image.path);
    expect(content.images.single.name, 'preview.png');
    expect(content.text, '请看  这张图片');
  });

  test('deduplicates image references and ignores other files', () {
    final content = parseAiUserMessageImages(
      '@preview.png @preview.png @notes.txt',
      workspaceRoot: directory.path,
      usesPosixPaths: true,
    );

    expect(content.images, hasLength(1));
    expect(content.text, '@notes.txt');
  });

  testWidgets('user bubble renders the image above the remaining prose', (
    tester,
  ) async {
    await tester.pumpWidget(harness('请看 @preview.png 这张图片'));
    await tester.pumpAndSettle();

    expect(find.byType(AiUserMessageImages), findsOneWidget);
    expect(find.text('请看  这张图片'), findsOneWidget);
    expect(find.textContaining('@preview.png'), findsNothing);
    expect(
      tester.getTopLeft(find.byType(AiUserMessageImages)).dy,
      lessThan(tester.getTopLeft(find.text('请看  这张图片')).dy),
    );
  });

  testWidgets('attachments render in a separate card above the text bubble', (
    tester,
  ) async {
    await tester.pumpWidget(harness('请看 @preview.png 这张图片'));
    await tester.pumpAndSettle();

    final attachment = find.byType(AiUserMessageImages);
    final text = find.text('请看  这张图片');
    expect(
      tester.getBottomLeft(attachment).dy,
      lessThan(tester.getTopLeft(text).dy),
    );
    final bubbleColors = tester
        .widgetList<ColoredBox>(
          find.ancestor(of: attachment, matching: find.byType(ColoredBox)),
        )
        .map((box) => box.color);
    expect(bubbleColors, isNot(contains(Colors.blue.shade100)));
  });

  testWidgets('attachment card has no padding and uses the hand cursor', (
    tester,
  ) async {
    await tester.pumpWidget(harness('@preview.png', onOpen: (_) {}));
    await tester.pumpAndSettle();

    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.mouseCursor, SystemMouseCursors.click);
    expect(tester.getSize(find.byType(InkWell)).width, lessThanOrEqualTo(280));
    expect(
      find.descendant(
        of: find.byType(AiUserMessageImages),
        matching: find.byType(Padding),
      ),
      findsNothing,
    );
  });

  testWidgets('tapping an attachment opens its original image', (tester) async {
    AiUserMessageImage? opened;
    await tester.pumpWidget(
      harness('@preview.png', onOpen: (image) => opened = image),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(opened?.path, image.path);
    expect(opened?.name, 'preview.png');
  });

  testWidgets('an image-only message does not render an empty text part', (
    tester,
  ) async {
    await tester.pumpWidget(harness('@preview.png'));
    await tester.pumpAndSettle();

    expect(find.byType(AiUserMessageImages), findsOneWidget);
    expect(find.byType(AiTextPartView), findsNothing);
  });

  testWidgets('a missing image falls back to its filename', (tester) async {
    await tester.pumpWidget(harness('@missing.png'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.text('missing.png'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing keeps the original attachment reference', (
    tester,
  ) async {
    await tester.pumpWidget(harness('请看 @preview.png', editing: true));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '请看 @preview.png');
  });
}
