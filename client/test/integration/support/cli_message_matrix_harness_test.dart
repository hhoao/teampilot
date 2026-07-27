import 'package:flutter_test/flutter_test.dart';
import 'package:mock_model_gateway/scenarios/simple_3turn.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/terminal/pending_user_message.dart';

import '../../support/post_frame_test_harness.dart';
import 'chat_thread_assertions.dart';
import 'cli_message_matrix_harness.dart';
import 'cli_test_profile.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('startGateway + writeMockProviders for simple claude cell', () async {
    final harness = CliMessageMatrixHarness.forCli(
      CliTool.claude,
      mode: CliMatrixMode.simple,
    );
    addTearDown(harness.dispose);

    expect(harness.recipe, CliMatrixRecipe.simple3Turn);
    await harness.startGateway();
    await harness.writeMockProviders();

    final providers = await AppProviderRepository(
      basePath: AppStorage.paths.basePath,
    ).loadProviders(CliTool.claude);
    expect(providers, hasLength(1));
    expect(providers.single.id, kMatrixSimpleProviderId);
    expect(providers.single.apiKey, simpleScriptApiKey);
    expect(providers.single.baseUrl, harness.mockBaseUrl);

    expect(harness.gateway!.requestLog, isEmpty);
    final dump = harness.diagnosticsBundle();
    expect(dump, contains('MockModelGatewayServer'));
    expect(dump, contains('mode=simple'));
  });

  test('homogeneous team builders pin row CLI on every member', () {
    for (final mode in [CliMatrixMode.native, CliMatrixMode.mixed]) {
      final harness = CliMessageMatrixHarness(
        profile: CliTestProfiles.forTool(CliTool.opencode),
        mode: mode,
      );
      if (mode == CliMatrixMode.native) {
        expect(
          () => harness.buildHomogeneousTeam(),
          throwsStateError,
          reason: 'opencode native must throw (unsupported)',
        );
        continue;
      }
      final team = harness.buildHomogeneousTeam();
      expect(team.cli, CliTool.opencode);
      expect(team.teamMode, TeamMode.mixed);
      expect(
        team.members.every((m) => (m.cli ?? team.cli) == CliTool.opencode),
        isTrue,
      );
    }
  });

  test('defaultRecipeFor maps modes', () {
    expect(
      CliMessageMatrixHarness.defaultRecipeFor(CliMatrixMode.simple),
      CliMatrixRecipe.simple3Turn,
    );
    expect(
      CliMessageMatrixHarness.defaultRecipeFor(CliMatrixMode.native),
      CliMatrixRecipe.nativeCollab3Plus,
    );
    expect(
      CliMessageMatrixHarness.defaultRecipeFor(CliMatrixMode.mixed),
      CliMatrixRecipe.mixedCollab3Plus,
    );
  });

  test('composeSeatAssistantMarkers are mode-aware', () {
    final profile = CliTestProfiles.forTool(CliTool.claude);
    expect(
      CliMessageMatrixHarness(
        profile: profile,
        mode: CliMatrixMode.simple,
      ).composeSeatAssistantMarkers,
      profile.assistantVisibleMarkers,
    );
    expect(
      CliMessageMatrixHarness(
        profile: profile,
        mode: CliMatrixMode.simple,
      ).composeSeatAssistantMarkers,
      ['MARK_A1', 'MARK_A2', 'MARK_A3'],
    );
    for (final mode in [CliMatrixMode.native, CliMatrixMode.mixed]) {
      final harness = CliMessageMatrixHarness(profile: profile, mode: mode);
      expect(
        harness.composeSeatAssistantMarkers,
        profile.collabLeadMarkers,
        reason: '$mode must use collab lead markers, not MARK_A*',
      );
      expect(
        harness.composeSeatAssistantMarkers,
        isNot(equals(profile.assistantVisibleMarkers)),
      );
    }
  });

  test('redactMatrixSecrets masks sk- and Bearer tokens', () {
    final raw =
        'key=sk-abcdefghijklmnopqrstuvwxyz Authorization: Bearer abcdefghijklmnop';
    final redacted = redactMatrixSecrets(raw);
    expect(redacted, contains('sk-[REDACTED]'));
    expect(redacted, contains('Bearer [REDACTED]'));
    expect(redacted, isNot(contains('sk-abcdefgh')));
    expect(redacted, isNot(contains('abcdefghijklmnop')));
  });

  test('truncateMatrixDumpLastLines keeps only the tail', () {
    final lines = [for (var i = 0; i < 5; i++) 'line-$i'];
    final out = truncateMatrixDumpLastLines(lines.join('\n'), maxLines: 2);
    expect(out, startsWith('… (3 lines truncated)'));
    expect(out, contains('line-3'));
    expect(out, contains('line-4'));
    expect(out, isNot(contains('line-0')));
  });

  test('sanitizeMatrixPtyDump truncates and redacts', () {
    final lines = [
      for (var i = 0; i < 10; i++) 'row-$i',
      'secret sk-abcdefghijklmnopqrstuvwxyz',
    ];
    final out = sanitizeMatrixPtyDump(lines.join('\n'), maxLines: 3);
    expect(out, startsWith('… (8 lines truncated)'));
    expect(out, contains('sk-[REDACTED]'));
    expect(out, isNot(contains('sk-abcdefgh')));
  });

  test('mailbox Queued snapshot survives promote for timeline assert', () async {
    final harness = CliMessageMatrixHarness.forCli(
      CliTool.claude,
      mode: CliMatrixMode.mixed,
    );
    const mailId = 'mail-99';
    const text = 'operator mailbox text';
    harness.mailboxQueued.add(
      const PendingUserMessage(id: mailId, content: text),
    );
    harness.mailboxQueuedSubmitted.add(
      const PendingUserMessage(id: mailId, content: text),
    );

    // Minimal history cubit not needed for promote if history is null —
    // attach via createCubit would be heavy; call append path manually.
    final postFrame = PostFrameTestHarness();
    harness.createCubit(postFrame: postFrame);
    addTearDown(harness.dispose);

    // Seat-isolated cubit: timeline refresh no-ops until a seat is focused via load.
    final session = AppSession(
      sessionId: 'sess-matrix-sticky',
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/work')],
      cli: CliTool.claude,
      createdAt: 1,
      updatedAt: 1,
    );
    await harness.history!.load(
      session: session,
      memberId: '',
      launchContext: WorkspaceLaunchContext(
        session: session,
        workspace: Workspace(
          workspaceId: session.workspaceId,
          folders: session.folders,
          createdAt: 0,
        ),
      ),
    );

    await harness.promoteMailboxConsumed(mailId);
    expect(harness.mailboxQueued, isEmpty);
    expect(harness.mailboxQueuedSubmitted, hasLength(1));
    expectMailboxQueuedThenTimeline(
      queuedSnapshot: harness.mailboxQueuedSubmitted,
      history: harness.history!,
      text: text,
      mailId: mailId,
    );
  });
}
