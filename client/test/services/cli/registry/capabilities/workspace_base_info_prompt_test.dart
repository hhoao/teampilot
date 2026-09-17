import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/cli/registry/capabilities/workspace_base_info_capability.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_targets.dart';

void main() {
  test('compose is empty without extras or ssh MCP', () {
    expect(composeWorkspaceBaseInfoPrompt(const WorkspaceSeatSnapshot()), '');
  });

  test('compose lists same-host extras only', () {
    final text = composeWorkspaceBaseInfoPrompt(
      const WorkspaceSeatSnapshot(sameHostExtraDirs: ['/repo/a', ' /repo/b ']),
    );
    expect(text, contains('## Workspace directories'));
    expect(text, contains('already authorized'));
    expect(text, contains('- /repo/a'));
    expect(text, contains('- /repo/b'));
    expect(text, isNot(contains('## Remote projects')));
    expect(text, isNot(contains('ssh')));
  });

  test('compose remote section when ssh MCP injected', () {
    final remote = WorkspaceRemoteFolderInfo.fromTarget(
      SessionSshMcpTarget(
        profile: const SshProfile(
          id: 'home-server',
          name: 'Home',
          host: '192.168.1.8',
          port: 22,
          username: 'alice',
        ),
        folderPaths: const ['/home/alice/proj', '/home/alice/other'],
      ),
    );
    final text = composeWorkspaceBaseInfoPrompt(
      WorkspaceSeatSnapshot(
        sshMcpInjected: true,
        remoteFolders: [remote],
      ),
    );
    expect(text, isNot(contains('## Workspace directories')));
    expect(text, contains('## Remote projects'));
    expect(text, contains('not on this machine'));
    expect(text, contains('list-servers'));
    expect(text, contains('execute-command'));
    expect(text, contains('upload'));
    expect(text, contains('download'));
    expect(text, contains('connectionName'));
    expect(text, contains('profileId'));
    expect(text, contains('Home (`home-server`)'));
    expect(text, contains('alice@192.168.1.8:22'));
    expect(text, contains('/home/alice/proj'));
    expect(text, contains('/home/alice/other'));
    expect(text, isNot(contains('password')));
    expect(text, isNot(contains('mcp__ssh__')));
    expect(text, isNot(contains('Mcp(ssh:')));
  });

  test('remote folders without sshMcpInjected are omitted', () {
    final remote = WorkspaceRemoteFolderInfo(
      profileId: 'home-server',
      name: 'Home',
      endpoint: 'alice@192.168.1.8:22',
      folderPaths: const ['/home/alice/proj'],
    );
    expect(
      composeWorkspaceBaseInfoPrompt(
        WorkspaceSeatSnapshot(remoteFolders: [remote]),
      ),
      isEmpty,
    );
  });

  test('extras plus ssh MCP include both sections', () {
    final text = composeWorkspaceBaseInfoPrompt(
      const WorkspaceSeatSnapshot(
        sameHostExtraDirs: ['/repo/a'],
        sshMcpInjected: true,
        remoteFolders: [
          WorkspaceRemoteFolderInfo(
            profileId: 'p',
            name: 'Box',
            endpoint: 'u@h:22',
            folderPaths: ['/r'],
          ),
        ],
      ),
    );
    expect(text, contains('## Workspace directories'));
    expect(text, contains('## Remote projects'));
    expect(text.indexOf('## Workspace directories'), lessThan(text.indexOf('## Remote projects')));
  });

  test('customPromptSections append after remote', () {
    final text = composeWorkspaceBaseInfoPrompt(
      const WorkspaceSeatSnapshot(
        sameHostExtraDirs: ['/repo/a'],
        customPromptSections: ['## Custom\nHello'],
      ),
    );
    expect(text, contains('- /repo/a'));
    expect(text, contains('## Custom'));
    expect(text, contains('Hello'));
    expect(text.indexOf('/repo/a'), lessThan(text.indexOf('## Custom')));
  });

  test('sshMcpInjected with empty remoteFolders still mentions mcp', () {
    final text = composeWorkspaceBaseInfoPrompt(
      const WorkspaceSeatSnapshot(sshMcpInjected: true),
    );
    expect(text, contains('## Remote projects'));
    expect(text, contains('list-servers'));
  });
}
