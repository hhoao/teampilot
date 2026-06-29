import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/models/home_closed_workspace_entry.dart';
import 'package:teampilot/models/launch_profile_ref.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';

void main() {
  final l10n = AppLocalizationsEn();
  const personal =
      LaunchProfileRef(LaunchProfileProvisioner.defaultPersonalId);
  const team = LaunchProfileRef('team-alpha');

  final identities = [
    PersonalProfile(
      id: LaunchProfileProvisioner.defaultPersonalId,
      display: 'Personal',
      createdAt: 0,
    ),
    TeamProfile(
      id: 'team-alpha',
      name: 'Alpha Team',
      cli: CliTool.claude,
      members: const [],
      createdAt: 0,
    ),
  ];

  test('recentlyClosedEntryLabel falls back to workspace id', () {
    expect(
      recentlyClosedEntryLabel(
        const HomeClosedWorkspaceEntry(
          workspaceId: 'proj-a',
          displayName: '',
          identity: personal,
        ),
      ),
      'proj-a',
    );
  });

  test('recentlyClosedSubtitleLine shows path only for personal singleton', () {
    const entry = HomeClosedWorkspaceEntry(
      workspaceId: 'proj-a',
      displayName: 'Alpha',
      primaryPath: '/tmp/a',
      identity: personal,
    );
    expect(
      recentlyClosedSubtitleLine(
        l10n: l10n,
        entry: entry,
        entries: const [entry],
        identities: identities,
      ),
      '/tmp/a',
    );
  });

  test('recentlyClosedSubtitleLine prefixes team identity', () {
    const entry = HomeClosedWorkspaceEntry(
      workspaceId: 'proj-a',
      displayName: 'Alpha',
      primaryPath: '/tmp/a',
      identity: team,
    );
    expect(
      recentlyClosedSubtitleLine(
        l10n: l10n,
        entry: entry,
        entries: const [entry],
        identities: identities,
      ),
      'Alpha Team · /tmp/a',
    );
  });

  test('recentlyClosedSubtitleLine prefixes identity for duplicate directories',
      () {
    const personalEntry = HomeClosedWorkspaceEntry(
      workspaceId: 'proj-a',
      displayName: 'Alpha',
      primaryPath: '/tmp/a',
      identity: personal,
    );
    const teamEntry = HomeClosedWorkspaceEntry(
      workspaceId: 'proj-a',
      displayName: 'Alpha',
      primaryPath: '/tmp/a',
      identity: team,
    );
    expect(
      recentlyClosedSubtitleLine(
        l10n: l10n,
        entry: personalEntry,
        entries: const [personalEntry, teamEntry],
        identities: identities,
      ),
      'Personal · /tmp/a',
    );
  });

  test('recentlyClosedTopology prefers live workspace folders', () {
    const entry = HomeClosedWorkspaceEntry(
      workspaceId: 'proj-a',
      displayName: 'Alpha',
      identity: personal,
      topology: WorkspaceTopology.local,
    );
    final workspace = Workspace(
      workspaceId: 'proj-a',
      folders: const [
        WorkspaceFolder(path: '/remote', targetId: 'ssh:host'),
      ],
      createdAt: 0,
    );
    expect(
      recentlyClosedTopology(entry: entry, workspace: workspace),
      WorkspaceTopology.remote,
    );
  });

  test('recentlyClosedTopology falls back to stored snapshot', () {
    const entry = HomeClosedWorkspaceEntry(
      workspaceId: 'proj-a',
      displayName: 'Alpha',
      identity: personal,
      topology: WorkspaceTopology.mixed,
    );
    expect(
      recentlyClosedTopology(entry: entry, workspace: null),
      WorkspaceTopology.mixed,
    );
  });
}
