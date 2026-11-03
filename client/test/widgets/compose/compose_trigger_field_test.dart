import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_catalog.dart';
import 'package:teampilot/services/commands/shortcut_context.dart';
import 'package:teampilot/services/commands/shortcut_dispatcher.dart';
import 'package:teampilot/services/cli/registry/capabilities/native_command_capability.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_clip.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_text_controller.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_token_document.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_text_edit.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/compose/compose_trigger_field.dart';

/// End-to-end regression test for the Task 6 review finding: while the `/`
/// suggestion overlay is open, Enter must pick the highlighted suggestion —
/// not also fire `compose.submit` via the root [ShortcutDispatcher].
///
/// Installs a real [ShortcutDispatcher] on [HardwareKeyboard] (like
/// `ShortcutDispatcherHost` in `main.dart`) alongside [ComposeTriggerField],
/// and drives Enter through [WidgetTester.sendKeyEvent] so both the global
/// hardware-keyboard path and the field's own `Focus.onKeyEvent` chain fire
/// exactly as they do in the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skill = Skill(
    id: 'skill-1',
    name: 'Plan',
    description: '',
    directory: 'plan',
    installedAt: 0,
    updatedAt: 0,
  );

  Future<void> pumpField(
    WidgetTester tester, {
    required CommandBus bus,
    required ComposeTextController controller,
    required FocusNode focusNode,
    required VoidCallback onSubmit,
    List<NativeCommand> nativeCommands = const [],
  }) async {
    await tester.pumpWidget(
      RepositoryProvider<CommandBus>.value(
        value: bus,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ComposeTriggerField(
              controller: controller,
              focusNode: focusNode,
              hint: 'Ask anything',
              enabled: true,
              onChanged: (_) {},
              onSubmit: onSubmit,
              canSubmit: () => true,
              workspaceRoot: '/tmp',
              skills: [skill],
              plugins: const [],
              slashBundle: const ConfigBundle(skillIds: ['skill-1']),
              nativeCommands: nativeCommands,
              mutedColor: Colors.black,
              hintColor: Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> enterComposeText(WidgetTester tester, String text) async {
    final field = tester.widget<ExtendedTextField>(
      find.byType(ExtendedTextField),
    );
    field.controller!.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    await tester.pump();
  }

  testWidgets('native command shows source and inserts argument space', (
    tester,
  ) async {
    final bus = CommandBus();
    final controller = ComposeTextController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpField(
      tester,
      bus: bus,
      controller: controller,
      focusNode: focusNode,
      onSubmit: () {},
      nativeCommands: const [
        NativeCommand(
          name: 'goal',
          description: NativeCommandDescription.goal,
          argumentHint: '<objective>',
        ),
      ],
    );

    focusNode.requestFocus();
    await tester.pump();
    await enterComposeText(tester, '/go');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('/goal'), findsWidgets);
    expect(find.textContaining('Native'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.text, '/goal ');
  });

  testWidgets('zero-argument native command inserts without a space', (
    tester,
  ) async {
    final bus = CommandBus();
    final controller = ComposeTextController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpField(
      tester,
      bus: bus,
      controller: controller,
      focusNode: focusNode,
      onSubmit: () {},
      nativeCommands: const [
        NativeCommand(name: 'help', description: NativeCommandDescription.help),
      ],
    );

    focusNode.requestFocus();
    await tester.pump();
    await enterComposeText(tester, '/he');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.text, '/help');
  });

  ShortcutDispatcher installDispatcher(CommandBus bus) {
    final dispatcher = ShortcutDispatcher(
      bus: bus,
      effectiveChords: (commandId) => CommandCatalog.v1
          .firstWhere((def) => def.id == commandId)
          .defaultChords,
      context: () => const ShortcutContext(inCompose: true, inTextInput: true),
      isMacOS: () => false,
    );
    dispatcher.attach();
    return dispatcher;
  }

  testWidgets(
    'Enter picks the suggestion instead of submitting while overlay is open',
    (tester) async {
      final bus = CommandBus();
      final controller = ComposeTextController();
      final focusNode = FocusNode();
      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
      });
      var submitCount = 0;

      await pumpField(
        tester,
        bus: bus,
        controller: controller,
        focusNode: focusNode,
        onSubmit: () => submitCount++,
      );
      final dispatcher = installDispatcher(bus);
      addTearDown(dispatcher.detach);

      focusNode.requestFocus();
      await tester.pump();

      await enterComposeText(tester, '/plan');
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      expect(find.text('/plan'), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        submitCount,
        0,
        reason: 'Enter must select the suggestion, not submit',
      );
      expect(controller.text, '/plan ');

      // Overlay is closed now: submit is re-registered, so a bare Enter
      // submits normally again.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(submitCount, 1);
    },
  );

  testWidgets(
    'Enter submits instead of applying a suggestion for an older query',
    (tester) async {
      final bus = CommandBus();
      final controller = ComposeTextController();
      final focusNode = FocusNode();
      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
      });
      var submitCount = 0;

      await pumpField(
        tester,
        bus: bus,
        controller: controller,
        focusNode: focusNode,
        onSubmit: () => submitCount++,
      );
      final dispatcher = installDispatcher(bus);
      addTearDown(dispatcher.detach);

      focusNode.requestFocus();
      await tester.pump();

      // A settled search populates the overlay for query "p".
      await enterComposeText(tester, '/p');
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(find.text('/plan'), findsWidgets);

      // Keep typing CJK text (no whitespace, so the trigger keeps growing)
      // and press Enter before the debounced search resolves the new query.
      await enterComposeText(tester, '/p你好世界');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(
        controller.text,
        '/p你好世界',
        reason: 'a suggestion for the old query must not replace the draft',
      );
      expect(submitCount, 1, reason: 'Enter submits the draft instead');
    },
  );

  testWidgets('tapping blank area inside the shell focuses the field', (
    tester,
  ) async {
    final bus = CommandBus();
    final controller = ComposeTextController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpField(
      tester,
      bus: bus,
      controller: controller,
      focusNode: focusNode,
      onSubmit: () {},
    );

    expect(focusNode.hasFocus, isFalse);

    // Create a leftover gap between shell and intrinsic line metrics, then
    // tap that blank region — it must still hit the expanding TextField.
    final grip = find.byKey(const Key('tp-textarea-resize-grip'));
    await tester.drag(grip, const Offset(0, 37));
    await tester.pump();

    final shellRect = tester.getRect(find.byType(ComposeTriggerField));
    await tester.tapAt(Offset(shellRect.center.dx, shellRect.bottom - 12));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);

    await enterComposeText(tester, 'from blank tap');
    await tester.pump();
    expect(controller.text, 'from blank tap');
  });

  testWidgets(
    'does not nest LayoutBuilder around the token field (landing open path)',
    (tester) async {
      final bus = CommandBus();
      final controller = ComposeTextController();
      final focusNode = FocusNode();
      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
      });

      await pumpField(
        tester,
        bus: bus,
        controller: controller,
        focusNode: focusNode,
        onSubmit: () {},
      );

      // Nested LayoutBuilder between ComposeTriggerField and TpTextareaShell
      // forces BUILD during parent layout and spikes landing first-open.
      final shell = find.byType(TpTextareaShell);
      expect(shell, findsOneWidget);
      var nestedLayoutBuilder = false;
      tester.element(shell).visitAncestorElements((ancestor) {
        if (ancestor.widget is ComposeTriggerField) return false;
        if (ancestor.widget is LayoutBuilder) {
          nestedLayoutBuilder = true;
          return false;
        }
        return true;
      });
      expect(nestedLayoutBuilder, isFalse);

      focusNode.requestFocus();
      await tester.pump();
      await enterComposeText(tester, 'still editable');
      await tester.pump();
      expect(controller.text, 'still editable');
    },
  );

  testWidgets('typing works after dragging the resize grip', (tester) async {
    final bus = CommandBus();
    final controller = ComposeTextController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpField(
      tester,
      bus: bus,
      controller: controller,
      focusNode: focusNode,
      onSubmit: () {},
    );

    final grip = find.byKey(const Key('tp-textarea-resize-grip'));
    expect(grip, findsOneWidget);

    await tester.drag(grip, const Offset(0, 24));
    await tester.pump();

    focusNode.requestFocus();
    await tester.pump();

    await enterComposeText(tester, 'hello after resize');
    await tester.pump();

    expect(controller.text, 'hello after resize');
  });

  group('image paste', () {
    Future<void> pumpFieldForPaste(
      WidgetTester tester, {
      required ComposeTextController controller,
      required FocusNode focusNode,
      required Future<bool> Function() onPasteImage,
    }) async {
      final bus = CommandBus();
      await tester.pumpWidget(
        RepositoryProvider<CommandBus>.value(
          value: bus,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ComposeTriggerField(
                controller: controller,
                focusNode: focusNode,
                hint: 'Ask anything',
                enabled: true,
                onChanged: (_) {},
                onSubmit: () {},
                canSubmit: () => true,
                workspaceRoot: '/tmp',
                skills: const [],
                plugins: const [],
                slashBundle: const ConfigBundle(),
                mutedColor: Colors.black,
                hintColor: Colors.grey,
                onPasteImage: onPasteImage,
              ),
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
    }

    Future<void> pressCtrlV(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    // Regression: a clipboard that holds an image AND text (GNOME/Explorer
    // "copy image file") used to insert both the imported @-reference and the
    // bare path: the field's HardwareKeyboard Ctrl+V listener imported the
    // image, and EditableText's default PasteTextIntent pasted the path text.
    // The fix re-routes the paste chord through the field's own
    // Shortcuts/Action layer so an image import swallows the key entirely.
    // (EditableText's default keyboard paste does not run under the test
    // harness on this SDK, so the widget-level double-insert itself cannot be
    // reproduced here; these tests pin the re-route contract instead.)
    testWidgets(
      'image paste inserts the reference and swallows the paste key',
      (tester) async {
        final controller = ComposeTextController();
        final focusNode = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focusNode.dispose);
        var pasteImageCalls = 0;

        await pumpFieldForPaste(
          tester,
          controller: controller,
          focusNode: focusNode,
          onPasteImage: () async {
            pasteImageCalls += 1;
            // Image import: inserts the @-reference like the real handler.
            controller.value = insertTextAtSelection(
              controller,
              '@/tmp/attachments/imported.png ',
            );
            return true;
          },
        );

        await pressCtrlV(tester);

        expect(controller.text, '@/tmp/attachments/imported.png ');
        expect(
          pasteImageCalls,
          1,
          reason: 'exactly one image import per paste',
        );
      },
    );

    testWidgets('text paste falls through when the clipboard has no image', (
      tester,
    ) async {
      final controller = ComposeTextController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      var pasteImageCalls = 0;

      await pumpFieldForPaste(
        tester,
        controller: controller,
        focusNode: focusNode,
        onPasteImage: () async {
          pasteImageCalls += 1;
          return false;
        },
      );

      await pressCtrlV(tester);

      // The image probe ran once and declined; nothing was inserted by it.
      expect(pasteImageCalls, 1);
      expect(controller.text, isEmpty);
    });
  });

  group('paste collapse', () {
    Future<void> pumpWithClip(
      WidgetTester tester, {
      required ComposeTextController controller,
      required FocusNode focusNode,
      required ComposeClip clip,
    }) async {
      final bus = CommandBus();
      await tester.pumpWidget(
        RepositoryProvider<CommandBus>.value(
          value: bus,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ComposeTriggerField(
                controller: controller,
                focusNode: focusNode,
                hint: 'Ask anything',
                enabled: true,
                onChanged: (_) {},
                onSubmit: () {},
                canSubmit: () => true,
                workspaceRoot: '/tmp',
                skills: const [],
                plugins: const [],
                slashBundle: const ConfigBundle(),
                mutedColor: Colors.black,
                hintColor: Colors.grey,
                clip: clip,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('oversized single insert collapses into the clip and clears', (
      tester,
    ) async {
      final controller = ComposeTextController();
      final focusNode = FocusNode();
      final clip = ComposeClip();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(clip.dispose);

      await pumpWithClip(
        tester,
        controller: controller,
        focusNode: focusNode,
        clip: clip,
      );

      final longText = List.generate(30, (i) => 'line $i').join('\n');
      // Assign text + selection as one value, exactly like a real paste at the
      // EditableText level. A separate `controller.selection =` after
      // `controller.text =` would run against the already-cleared controller:
      // the collapse fires synchronously inside the change listener.
      controller.value = TextEditingValue(
        text: longText,
        selection: TextSelection.collapsed(offset: longText.length),
      );
      await tester.pump();

      expect(clip.collapsed, isTrue);
      expect(clip.text, longText);
      expect(controller.text, isEmpty);
    });

    testWidgets('small paste does not collapse', (tester) async {
      final controller = ComposeTextController();
      final focusNode = FocusNode();
      final clip = ComposeClip();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(clip.dispose);

      await pumpWithClip(
        tester,
        controller: controller,
        focusNode: focusNode,
        clip: clip,
      );

      controller.text = 'small\npaste';
      await tester.pump();

      expect(clip.collapsed, isFalse);
      expect(controller.text, 'small\npaste');
    });
  });

  testWidgets('a hand-typed @mention is never a token', (tester) async {
    final bus = CommandBus();
    final controller = ComposeTextController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpField(
      tester,
      bus: bus,
      controller: controller,
      focusNode: focusNode,
      onSubmit: () {},
    );
    focusNode.requestFocus();
    await tester.pump();

    await enterComposeText(tester, '@src/main.dart');
    await tester.pump();

    expect(controller.tokenRanges, isEmpty);
  });

  testWidgets('a pasted absolute path is not a token', (tester) async {
    final bus = CommandBus();
    final controller = ComposeTextController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpField(
      tester,
      bus: bus,
      controller: controller,
      focusNode: focusNode,
      onSubmit: () {},
    );
    focusNode.requestFocus();
    await tester.pump();

    await enterComposeText(tester, '/home/me/report.pdf 帮我总结');
    await tester.pump();

    expect(controller.tokenRanges, isEmpty);
  });

  testWidgets('a zero-argument command does not absorb following text', (
    tester,
  ) async {
    final bus = CommandBus();
    final controller = ComposeTextController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpField(
      tester,
      bus: bus,
      controller: controller,
      focusNode: focusNode,
      onSubmit: () {},
      nativeCommands: const [
        NativeCommand(name: 'help', description: NativeCommandDescription.help),
      ],
    );
    focusNode.requestFocus();
    await tester.pump();

    await enterComposeText(tester, '/he');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.text, '/help');
    expect(controller.tokenRanges, [const TextRange(start: 0, end: 5)]);

    controller.text = '/help你好世界';
    await tester.pump();

    expect(controller.tokenRanges, [const TextRange(start: 0, end: 5)]);
  });

  testWidgets('backspace deletes an inserted token as one unit', (
    tester,
  ) async {
    final bus = CommandBus();
    final controller = ComposeTextController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpField(
      tester,
      bus: bus,
      controller: controller,
      focusNode: focusNode,
      onSubmit: () {},
    );
    focusNode.requestFocus();
    await tester.pump();

    await enterComposeText(tester, '/pl');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    focusNode.requestFocus();
    await tester.pump();
    expect(find.text('/plan'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.text, '/plan ');

    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(controller.text, ' ');
    expect(controller.tokenRanges, isEmpty);
  });

  testWidgets('token ranges follow text inserted before the token', (
    tester,
  ) async {
    final bus = CommandBus();
    final controller = ComposeTextController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpField(
      tester,
      bus: bus,
      controller: controller,
      focusNode: focusNode,
      onSubmit: () {},
    );

    controller.insertToken(
      start: 0,
      end: 0,
      tokenText: '/plan',
      suffix: ' ',
      kind: ComposeTokenKind.skill,
      payload: '/plan',
    );
    await tester.pump();

    controller.text = 'x ${controller.text}';
    await tester.pump();

    expect(controller.tokenRanges, [const TextRange(start: 2, end: 7)]);
  });

  testWidgets('arrow keys cross a token and its separator in one press', (
    tester,
  ) async {
    final bus = CommandBus();
    final controller = ComposeTextController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpField(
      tester,
      bus: bus,
      controller: controller,
      focusNode: focusNode,
      onSubmit: () {},
    );
    final dispatcher = installDispatcher(bus);
    addTearDown(dispatcher.detach);
    await enterComposeText(tester, '/pl');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    focusNode.requestFocus();
    await tester.pump();
    expect(find.text('/plan'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.text, '/plan ');

    controller.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.selection.baseOffset, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.selection.baseOffset, 6);
  });

  testWidgets('selected token renders a padded inline chip', (tester) async {
    final bus = CommandBus();
    final controller = ComposeTextController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpField(
      tester,
      bus: bus,
      controller: controller,
      focusNode: focusNode,
      onSubmit: () {},
    );
    final dispatcher = installDispatcher(bus);
    addTearDown(dispatcher.detach);
    await enterComposeText(tester, '/pl');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    final label = find.text('/plan');
    expect(label, findsWidgets);
    final padded = find
        .ancestor(of: label, matching: find.byType(Container))
        .evaluate()
        .map((element) => element.widget as Container)
        .where(
          (container) =>
              container.padding ==
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        );
    expect(padded, isNotEmpty);
  });
}
