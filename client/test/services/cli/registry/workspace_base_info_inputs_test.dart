import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/cli/registry/capabilities/workspace_base_info_capability.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_constants.dart';

SshProfile _profile(String id, {String name = ''}) => SshProfile(
  id: id,
  name: name.isEmpty ? id : name,
  host: '$id.example',
  username: 'alice',
);

void main() {
  test('extra without ssh key leaves sshMcpInjected false', () {
    final inputs = workspaceBaseInfoPromptInputs(
      extraMcpServers: {
        'other': {'url': 'http://example'},
      },
    );
    expect(inputs.sshMcpInjected, isFalse);
    expect(inputs.remoteFolders, isEmpty);
  });

  test('extra with sessionSshMcpServerName sets sshMcpInjected true', () {
    final inputs = workspaceBaseInfoPromptInputs(
      extraMcpServers: {
        sessionSshMcpServerName: {'url': 'http://127.0.0.1/ssh/mcp'},
      },
    );
    expect(inputs.sshMcpInjected, isTrue);
  });

  test('ssh folders plus profileOf populate remoteFolders', () {
    final inputs = workspaceBaseInfoPromptInputs(
      folders: const [
        WorkspaceFolder(path: '/home/alice/proj', targetId: 'ssh:home-server'),
      ],
      profileOf: (id) =>
          id == 'home-server' ? _profile('home-server', name: 'Home') : null,
    );
    expect(inputs.remoteFolders, hasLength(1));
    expect(inputs.remoteFolders.single.profileId, 'home-server');
  });

  test(
    'null profileOf yields empty remoteFolders; inject still follows extra',
    () {
      final inputs = workspaceBaseInfoPromptInputs(
        extraMcpServers: {
          sessionSshMcpServerName: {'url': 'http://127.0.0.1/ssh/mcp'},
        },
        folders: const [
          WorkspaceFolder(
            path: '/home/alice/proj',
            targetId: 'ssh:home-server',
          ),
        ],
      );
      expect(inputs.sshMcpInjected, isTrue);
      expect(inputs.remoteFolders, isEmpty);
    },
  );
}
