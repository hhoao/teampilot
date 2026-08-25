import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:teampilot/services/compose/compose_clip.dart';
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
    required TextEditingController controller,
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

  testWidgets('native command shows source and inserts argument space', (
    tester,
  ) async {
    final bus = CommandBus();
    final controller = TextEditingController();
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
    await tester.enterText(find.byType(TextField), '/go');
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
    final controller = TextEditingController();
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
          name: 'help',
          description: NativeCommandDescription.help,
        ),
      ],
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.enterText(find.byType(TextField), '/he');
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
      context: () =>
          const ShortcutContext(inCompose: true, inTextInput: true),
      isMacOS: () => false,
    );
    dispatcher.attach();
    return dispatcher;
  }

  testWidgets(
    'Enter picks the suggestion instead of submitting while overlay is open',
    (tester) async {
      final bus = CommandBus();
      final controller = TextEditingController();
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

      await tester.enterText(find.byType(TextField), '/plan');
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

  testWidgets('tapping blank area inside the shell focuses the field', (
    tester,
  ) async {
    final bus = CommandBus();
    final controller = TextEditingController();
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

    await tester.enterText(find.byType(TextField), 'from blank tap');
    await tester.pump();
    expect(controller.text, 'from blank tap');
  });

  testWidgets(
    'does not nest LayoutBuilder around the token field (landing open path)',
    (tester) async {
      final bus = CommandBus();
      final controller = TextEditingController();
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
      await tester.enterText(find.byType(TextField), 'still editable');
      await tester.pump();
      expect(controller.text, 'still editable');
    },
  );

  testWidgets('typing works after dragging the resize grip', (tester) async {
    final bus = CommandBus();
    final controller = TextEditingController();
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

    await tester.enterText(find.byType(TextField), 'hello after resize');
    await tester.pump();

    expect(controller.text, 'hello after resize');
    expect(find.text('hello after resize'), findsWidgets);
  });

  group('paste collapse', () {
    Future<void> pumpWithClip(
      WidgetTester tester, {
      required TextEditingController controller,
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

    testWidgets('oversized single insert collapses into the clip and clears',
        (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final clip = ComposeClip();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(clip.dispose);

      await pumpWithClip(tester, controller: controller, focusNode: focusNode, clip: clip);

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
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final clip = ComposeClip();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(clip.dispose);

      await pumpWithClip(tester, controller: controller, focusNode: focusNode, clip: clip);

      controller.text = 'small\npaste';
      await tester.pump();

      expect(clip.collapsed, isFalse);
      expect(controller.text, 'small\npaste');
    });
  });
}
