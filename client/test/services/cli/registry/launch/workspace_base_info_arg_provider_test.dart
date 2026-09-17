import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/workspace_base_info_capability.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_contribution.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';
import 'package:teampilot/services/cli/registry/launch/workspace_access.dart';
import 'package:teampilot/services/resource/contribution/prompt_document.dart';
import 'package:teampilot/services/resource/providers/prompt_contribution_provider.dart';

void main() {
  const provider = _FakeWorkspaceBaseInfo();

  test(
    'filters blank directories and preserves repeated add-directory pairs',
    () {
      final context = _context(
        workingDirectory: '  /workspace  ',
        additionalDirectories: const [' ', '/repo/one', '', '/repo/two'],
      );

      expect(provider.buildLaunchArgs(context).toList(), [
        CliLaunchArgContribution(
          key: 'workspace',
          phase: LaunchArgPhase.workspace,
          args: [
            '--cwd',
            '/workspace',
            '--add-dir',
            '/repo/one',
            '--add-dir',
            '/repo/two',
          ],
        ),
      ]);
    },
  );

  test('normalizes primary and additional directories for WSL', () {
    final context = _context(
      workingDirectory: r'C:\work\project',
      additionalDirectories: const [r'D:\repo\one'],
      useWslPaths: true,
    );

    expect(provider.buildLaunchArgs(context).single.args, [
      '--cwd',
      '/mnt/c/work/project',
      '--add-dir',
      '/mnt/d/repo/one',
    ]);
  });

  test('emits no contribution when all workspace paths are blank', () {
    expect(
      provider
          .buildLaunchArgs(
            _context(
              workingDirectory: '  ',
              additionalDirectories: const [' ', ''],
            ),
          )
          .toList(),
      isEmpty,
    );
  });

  test('base provide emits workspace-base-info when extras exist', () async {
    final contributions = await const _FakeWorkspaceBaseInfo().provide(
      PromptProviderContext(
        cli: CliTool.claude,
        additionalDirectories: const ['/repo/a'],
      ),
    );
    expect(contributions.single.id, 'workspace-base-info');
    expect(contributions.single.origin.providerId, 'workspace-base-info');
    expect(contributions.single.scope, PromptScope.workspace);
    expect(contributions.single.mergeRole, PromptMergeRole.append);
    expect(contributions.single.content, contains('- /repo/a'));
  });

  test('base provide is empty without extras or ssh MCP', () async {
    expect(
      await const _FakeWorkspaceBaseInfo().provide(
        PromptProviderContext(cli: CliTool.claude),
      ),
      isEmpty,
    );
  });
}

CliLaunchContext _context({
  String? workingDirectory,
  List<String> additionalDirectories = const [],
  bool useWslPaths = false,
}) {
  return CliLaunchContext(
    team: TeamProfile(id: 'team', name: 'Team'),
    member: TeamMemberConfig(id: 'member', name: 'Member'),
    workingDirectory: workingDirectory,
    additionalDirectories: additionalDirectories,
    useWslPaths: useWslPaths,
  );
}

final class _FakeWorkspaceBaseInfo extends WorkspaceBaseInfoCapabilityBase {
  const _FakeWorkspaceBaseInfo();

  @override
  Iterable<CliLaunchArgContribution> buildWorkspaceAccessArgs(
    CliLaunchContext context,
    WorkspaceAccess access,
  ) {
    final args = <String>[];
    final workingDirectory = access.workingDirectory;
    if (workingDirectory != null) {
      args.addAll(['--cwd', workingDirectory]);
    }
    for (final directory in access.additionalDirectories) {
      args.addAll(['--add-dir', directory]);
    }
    return [
      CliLaunchArgContribution(
        key: 'workspace',
        phase: LaunchArgPhase.workspace,
        args: args,
      ),
    ];
  }
}
