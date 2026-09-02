import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/right_tools/tabbed_panel.dart';
import 'package:teampilot/widgets/right_tools/tool_view.dart';

Widget _wrap(Widget child, {required WorkspaceToolsCubit toolsCubit}) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB));
  return TpTheme(
    data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
    child: MaterialApp(
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: BlocProvider.value(value: toolsCubit, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('empty open set shows the open-tab picker', (tester) async {
    final toolsCubit = WorkspaceToolsCubit();
    addTearDown(toolsCubit.close);
    await tester.pumpWidget(
      _wrap(
        const TabbedPanel(
          views: [
            ToolView(
              id: 'members',
              icon: Icons.groups_outlined,
              label: 'Members',
              child: Text('members-body'),
            ),
            ToolView(
              id: 'mailbox',
              icon: Icons.mail_outline,
              label: 'Mailbox',
              child: Text('mailbox-body'),
            ),
          ],
        ),
        toolsCubit: toolsCubit,
      ),
    );

    expect(find.text('Open a tab'), findsOneWidget);
    expect(find.text('members-body'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('opening a picker tile mounts and keeps the body', (
    tester,
  ) async {
    final toolsCubit = WorkspaceToolsCubit();
    addTearDown(toolsCubit.close);
    await tester.pumpWidget(
      _wrap(
        TabbedPanel(
          scopeId: 'ws-1',
          views: const [
            ToolView(
              id: 'members',
              icon: Icons.groups_outlined,
              label: 'Members',
              child: Text('members-body'),
            ),
            ToolView(
              id: 'mailbox',
              icon: Icons.mail_outline,
              label: 'Mailbox',
              child: Text('mailbox-body'),
              badgeCount: 3,
            ),
          ],
        ),
        toolsCubit: toolsCubit,
      ),
    );

    await tester.tap(find.text('Mailbox'));
    await tester.pump();
    expect(find.text('mailbox-body'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(toolsCubit.openIdsFor('ws-1'), ['mailbox']);
  });

  testWidgets('persisted open tab shows on first frame', (tester) async {
    final toolsCubit = WorkspaceToolsCubit()
      ..ensureOpenAndSelect('ws-1', 'mailbox');
    addTearDown(toolsCubit.close);

    await tester.pumpWidget(
      _wrap(
        TabbedPanel(
          scopeId: 'ws-1',
          views: const [
            ToolView(
              id: 'members',
              icon: Icons.groups_outlined,
              label: 'Members',
              child: Text('members-body'),
            ),
            ToolView(
              id: 'mailbox',
              icon: Icons.mail_outline,
              label: 'Mailbox',
              child: Text('mailbox-body'),
            ),
          ],
        ),
        toolsCubit: toolsCubit,
      ),
    );

    expect(find.text('mailbox-body'), findsOneWidget);
  });

  testWidgets('closing the last tab returns to the picker', (tester) async {
    final toolsCubit = WorkspaceToolsCubit()
      ..ensureOpenAndSelect('ws-1', 'members');
    addTearDown(toolsCubit.close);

    await tester.pumpWidget(
      _wrap(
        TabbedPanel(
          scopeId: 'ws-1',
          views: const [
            ToolView(
              id: 'members',
              icon: Icons.groups_outlined,
              label: 'Members',
              child: Text('members-body'),
            ),
            ToolView(
              id: 'mailbox',
              icon: Icons.mail_outline,
              label: 'Mailbox',
              child: Text('mailbox-body'),
            ),
          ],
        ),
        toolsCubit: toolsCubit,
      ),
    );

    expect(find.text('members-body'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('Open a tab'), findsOneWidget);
    expect(find.text('members-body'), findsNothing);
  });
}
