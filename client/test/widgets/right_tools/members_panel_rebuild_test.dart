import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import 'package:teampilot/widgets/right_tools/members_panel.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

const _backend = TeamMemberConfig(id: 'm1', name: 'Backend');
const _frontend = TeamMemberConfig(id: 'm2', name: 'Frontend');
const _team = TeamProfile(
  id: 't',
  name: 'T',
  cli: CliTool.claude,
  members: [_backend, _frontend],
);

class _PresenceCubit extends MemberPresenceCubit {
  void replace(Map<String, MemberPresence> presence) {
    emit(MemberPresenceState(presence: presence));
  }
}

Widget _host({
  required AppProviderCubit providerCubit,
  required MemberPresenceCubit presenceCubit,
  required CliPresetsCubit cliPresetsCubit,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: providerCubit),
        BlocProvider.value(value: cliPresetsCubit),
        BlocProvider<MemberPresenceCubit>.value(value: presenceCubit),
      ],
      child: CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: Scaffold(
          body: MembersPanel(
            team: _team,
            members: const [_backend, _frontend],
            memberPresence: const {},
            providersByCli: const {},
            selectedMemberId: '',
            onSelected: _noop,
            onSwitchTo: _noop,
            onOpen: _noop,
            onLaunchAll: _noopVoid,
            canViewDetail: true,
            onViewDetail: _noop,
            onOpenConfigDir: _noop,
          ),
        ),
      ),
    ),
  );
}

void _noop(String _) {}
void _noopVoid() {}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late AppProviderCubit providerCubit;
  late _PresenceCubit presenceCubit;
  late CliPresetsCubit cliPresetsCubit;

  setUp(() {
    providerCubit = AppProviderCubit();
    presenceCubit = _PresenceCubit();
    cliPresetsCubit = CliPresetsCubit(
      repository: CliPresetsRepository(
        fs: InMemoryFilesystem(),
        presetsPath: '/cli-presets.json',
      ),
    );
  });

  tearDown(() async {
    await providerCubit.close();
    await presenceCubit.close();
    await cliPresetsCubit.close();
  });

  testWidgets(
    'this member cubit presence updates the tile without rebuilding MembersPanel',
    (tester) async {
      await tester.pumpWidget(
        _host(
          providerCubit: providerCubit,
          presenceCubit: presenceCubit,
          cliPresetsCubit: cliPresetsCubit,
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(MembersPanel)),
      );
      expect(
        find.descendant(
          of: find.byKey(AppKeys.memberRow(_backend.id)),
          matching: find.textContaining(l10n.memberPresenceOffline),
        ),
        findsOneWidget,
      );

      var panelRebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is MembersPanel) panelRebuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      presenceCubit.replace({
        _backend.id: const MemberPresence(
          connection: MemberConnection.connected,
          availability: MemberAvailability.working,
        ),
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.descendant(
          of: find.byKey(AppKeys.memberRow(_backend.id)),
          matching: find.textContaining(l10n.memberPresenceWorking),
        ),
        findsOneWidget,
      );
      expect(
        panelRebuilds,
        0,
        reason: 'presence must be selected on the member tile, not the panel',
      );
    },
  );

  testWidgets('other member cubit presence does not rebuild MembersPanel', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        providerCubit: providerCubit,
        presenceCubit: presenceCubit,
        cliPresetsCubit: cliPresetsCubit,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(MembersPanel)));
    var panelRebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is MembersPanel) panelRebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    presenceCubit.replace({
      _frontend.id: const MemberPresence(
        connection: MemberConnection.connected,
        availability: MemberAvailability.working,
      ),
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.descendant(
        of: find.byKey(AppKeys.memberRow(_backend.id)),
        matching: find.textContaining(l10n.memberPresenceOffline),
      ),
      findsOneWidget,
    );
    expect(panelRebuilds, 0);
  });
}
