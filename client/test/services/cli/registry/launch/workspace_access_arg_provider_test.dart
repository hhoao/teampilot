import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_contribution.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';
import 'package:teampilot/services/cli/registry/launch/workspace_access_arg_provider.dart';

void main() {
  const provider = _FakeWorkspaceAccessArgProvider();

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

final class _FakeWorkspaceAccessArgProvider extends WorkspaceAccessArgProvider {
  const _FakeWorkspaceAccessArgProvider();

  @override
  Iterable<CliLaunchArgContribution> buildWorkspaceAccessArgs(
    CliLaunchContext context,
    WorkspaceAccess access,
  ) {
    if (access.workingDirectory == null &&
        access.additionalDirectories.isEmpty) {
      return const [];
    }

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
