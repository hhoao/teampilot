import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/widgets/right_tools/members_panel.dart';

import '../../support/post_frame_test_harness.dart';

const _member = TeamMemberConfig(id: 'm1', name: 'Backend');
const _team = TeamProfile(id: 't', name: 'T', cli: CliTool.claude, members: [_member]);

Widget _host(Widget child, AppProviderCubit providerCubit) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BlocProvider.value(
        value: providerCubit,
        child: CliToolRegistryScope(
          registry: CliToolRegistry.builtIn(),
          child: Scaffold(body: child),
        ),
      ),
    );

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('right-click opens the member menu with view-detail', (tester) async {
    final providerCubit = AppProviderCubit();
    addTearDown(providerCubit.close);

    await tester.pumpWidget(_host(
      MembersPanel(
        team: _team,
        members: const [_member],
        memberPresence: const {},
        providersByCli: const {},
        selectedMemberId: '',
        onSelected: (_) {},
        onOpen: (_) {},
        onLaunchAll: () {},
        canViewDetail: true,
        onViewDetail: (_) {},
        onOpenConfigDir: (_) {},
      ),
      providerCubit,
    ));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(MembersPanel)),
    );

    await tester.tap(find.byKey(const Key('member-row-m1')),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text(l10n.memberDetailViewAction), findsOneWidget);
    expect(find.text(l10n.memberDetailOpenConfigDir), findsOneWidget);
  });

  testWidgets('tapping view-detail dispatches after the menu closes', (tester) async {
    final providerCubit = AppProviderCubit();
    addTearDown(providerCubit.close);

    String? viewedId;
    await tester.pumpWidget(_host(
      MembersPanel(
        team: _team,
        members: const [_member],
        memberPresence: const {},
        providersByCli: const {},
        selectedMemberId: '',
        onSelected: (_) {},
        onOpen: (_) {},
        onLaunchAll: () {},
        canViewDetail: true,
        onViewDetail: (id) => viewedId = id,
        onOpenConfigDir: (_) {},
      ),
      providerCubit,
    ));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(MembersPanel)),
    );

    await tester.tap(find.byKey(const Key('member-row-m1')),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.memberDetailViewAction));
    await tester.pumpAndSettle();

    expect(viewedId, 'm1');
    expect(find.text(l10n.memberDetailOpenConfigDir), findsNothing);
  });

  testWidgets('disabled view-detail does not dispatch', (tester) async {
    final providerCubit = AppProviderCubit();
    addTearDown(providerCubit.close);

    var viewed = false;
    await tester.pumpWidget(_host(
      MembersPanel(
        team: _team,
        members: const [_member],
        memberPresence: const {},
        providersByCli: const {},
        selectedMemberId: '',
        onSelected: (_) {},
        onOpen: (_) {},
        onLaunchAll: () {},
        canViewDetail: false,
        onViewDetail: (_) => viewed = true,
        onOpenConfigDir: (_) {},
      ),
      providerCubit,
    ));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(MembersPanel)),
    );

    await tester.tap(find.byKey(const Key('member-row-m1')),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.memberDetailViewAction));
    await tester.pumpAndSettle();

    expect(viewed, isFalse);
  });
}
