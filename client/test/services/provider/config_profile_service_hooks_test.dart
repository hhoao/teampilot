import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/config_profile/config_profile_context.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/resource/providers/hook_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/hook_library_contribution_provider.dart';
import 'package:teampilot/services/resource/resource_provider_set.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/cursor_lifecycle_test_paths.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late ConfigProfileLaunchContext Function({
    List<HookEntry>? hooks,
    List<HookContributionProvider> extraProviders,
    bool promptAlreadyMaterialized,
  })
  buildCtx;

  setUp(() {
    fs = InMemoryFilesystem();
    final paths = CursorLifecycleTestPaths(
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/data/tp', fs: fs),
    );
    final scope = const LaunchProfileScope(
      workspaceId: 'w',
      teamId: 't',
      sessionId: 's',
      cliTeamName: 's',
    );
    buildCtx =
        ({
          List<HookEntry>? hooks,
          List<HookContributionProvider> extraProviders = const [],
          bool promptAlreadyMaterialized = false,
        }) => ConfigProfileLaunchContext(
          workspaceId: 'w',
          teamId: 't',
          sessionId: 's',
          scope: scope,
          members: const [],
          paths: paths,
          catalog: paths,
          resourceProviders: ResourceProviderSet(
            hooks: [
              UserHookContributionProvider(entries: hooks ?? const []),
              ...extraProviders,
            ],
          ),
          promptAlreadyMaterialized: promptAlreadyMaterialized,
        );
  });

  test('ConfigProfileLaunchContext carries a single resource provider set', () {
    final ctx = buildCtx();
    expect(ctx.resourceProviders.hooks, hasLength(1));
    expect(ctx.resourceProviders.hooks.single.providerId, 'user-library');
  });

  test('hooks are threaded through constructor', () {
    final entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo hi'),
    );
    final ctx = buildCtx(hooks: [entry]);
    final provider =
        ctx.resourceProviders.hooks.single as UserHookContributionProvider;
    expect(provider.entries.single.id, 'h1');
  });

  test('session-home adapter preserves every injected hook provider', () {
    final ctx = buildCtx(
      extraProviders: [
        UserHookContributionProvider(
          entries: const [],
          providerId: 'managed-injected',
        ),
      ],
    );
    final home = sessionHomeContextFromLaunch(ctx, CliTool.claude);

    expect(
      home.resourceProviders.hooks.map((provider) => provider.providerId),
      ['user-library', 'managed-injected'],
    );
  });

  test('session-home adapter carries the coordinator prompt marker', () {
    final home = sessionHomeContextFromLaunch(
      buildCtx(promptAlreadyMaterialized: true),
      CliTool.claude,
    );

    expect(home.promptAlreadyMaterialized, isTrue);
  });
}
