import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/chat_message_action_menu.dart';

const _textMessage = AiMessage(
  id: 'm1',
  role: AiRole.assistant,
  parts: [AiTextPart(text: 'hello')],
);

const _emptyMessage = AiMessage(
  id: 'm2',
  role: AiRole.assistant,
  parts: [],
);

Future<BuildContext> _captureContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appLocalizationsSupportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return captured;
}

List<TpActionMenuSpec> _specs(
  BuildContext context, {
  AiMessage message = _textMessage,
  bool deliveryFailed = false,
  bool showsVersion = false,
  bool rewindEnabled = true,
  ChatMessageActionHandlers handlers = const ChatMessageActionHandlers(),
  required ChatMessageClipboardWriter writeClipboard,
  required ValueChanged<String> onFeedback,
}) {
  return buildChatMessageActionSpecs(
    context,
    message: message,
    deliveryFailed: deliveryFailed,
    showsVersion: showsVersion,
    rewindEnabled: rewindEnabled,
    handlers: handlers,
    writeClipboard: writeClipboard,
    onFeedback: onFeedback,
  );
}

void main() {
  testWidgets('plain message offers only copy + export markdown', (tester) async {
    final context = await _captureContext(tester);
    final specs = _specs(
      context,
      writeClipboard: (text) async {},
      onFeedback: (_) {},
    );
    expect(specs, hasLength(2));
    expect(specs[0].label, 'copy');
    expect(specs[0].enabled, isTrue);
    expect(specs[1].label, 'Export Markdown');
    expect(specs[1].enabled, isTrue);
  });

  testWidgets('empty message disables both clipboard actions', (tester) async {
    final context = await _captureContext(tester);
    final specs = _specs(
      context,
      message: _emptyMessage,
      writeClipboard: (text) async {},
      onFeedback: (_) {},
    );
    expect(specs, hasLength(2));
    expect(specs[0].enabled, isFalse);
    expect(specs[1].enabled, isFalse);
  });

  testWidgets('full menu keeps action-bar order and honours rewindEnabled', (tester) async {
    final context = await _captureContext(tester);
    final handlers = ChatMessageActionHandlers(
      onRetry: () {},
      onEdit: () {},
      onFork: () {},
      onPreviousVersion: () {},
      onNextVersion: () {},
    );
    final specs = _specs(
      context,
      deliveryFailed: true,
      showsVersion: true,
      rewindEnabled: false,
      handlers: handlers,
      writeClipboard: (text) async {},
      onFeedback: (_) {},
    );
    expect(specs, hasLength(9));
    expect(specs[0].label, 'Retry');
    expect(specs[1].label, 'copy');
    expect(specs[2].isDivider, isTrue);
    expect(specs[3].label, 'Edit message');
    expect(specs[4].label, 'Fork from here');
    expect(specs[5].label, 'Previous version');
    expect(specs[6].label, 'Next version');
    expect(specs[7].isDivider, isTrue);
    expect(specs[8].label, 'Export Markdown');
    // Only the rewind group is disabled; retry / clipboard stay enabled.
    for (final index in [3, 4, 5, 6]) {
      expect(specs[index].enabled, isFalse, reason: 'index $index');
    }
    expect(specs[0].enabled, isTrue);
    expect(specs[1].enabled, isTrue);
    expect(specs[8].enabled, isTrue);
  });

  testWidgets('menu actions invoke handlers and copy both text forms', (tester) async {
    final context = await _captureContext(tester);
    final calls = <String>[];
    final copied = <String>[];
    final feedback = <String>[];
    final specs = _specs(
      context,
      deliveryFailed: true,
      showsVersion: true,
      handlers: ChatMessageActionHandlers(
        onRetry: () => calls.add('retry'),
        onEdit: () => calls.add('edit'),
        onFork: () => calls.add('fork'),
        onPreviousVersion: () => calls.add('prev'),
        onNextVersion: () => calls.add('next'),
      ),
      writeClipboard: (text) async => copied.add(text),
      onFeedback: (message) => feedback.add(message),
    );
    for (final spec in specs.where((spec) => !spec.isDivider)) {
      spec.onAction?.call();
    }
    expect(calls, ['retry', 'edit', 'fork', 'prev', 'next']);
    expect(copied, ['hello', 'hello']);
    expect(feedback, ['Copied', 'Copied']);
  });

  testWidgets('showChatMessageActionMenu renders TpActionMenuItems', (tester) async {
    final context = await _captureContext(tester);
    unawaited(
      showChatMessageActionMenu(
        context,
        globalPosition: Offset.zero,
        message: _textMessage,
        deliveryFailed: false,
        showsVersion: false,
        rewindEnabled: true,
        handlers: const ChatMessageActionHandlers(),
        writeClipboard: (text) async {},
        onFeedback: (_) {},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TpActionMenuItem), findsNWidgets(2));
  });
}
