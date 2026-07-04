import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/models/home_closed_workspace_entry.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('recentlyClosedEntryLabel falls back to workspace id', () {
    expect(
      recentlyClosedEntryLabel(
        const HomeClosedWorkspaceEntry(workspaceId: 'proj-a', displayName: ''),
      ),
      'proj-a',
    );
  });

  test('recentlyClosedSubtitleLine shows path only', () {
    const entry = HomeClosedWorkspaceEntry(
      workspaceId: 'proj-a',
      displayName: 'Alpha',
      primaryPath: '/tmp/a',
    );
    expect(
      recentlyClosedSubtitleLine(
        l10n: l10n,
        entry: entry,
        entries: const [entry],
        identities: const [],
      ),
      '/tmp/a',
    );
  });

  test('recentlyClosedTopology prefers live workspace folders', () {
    const entry = HomeClosedWorkspaceEntry(
      workspaceId: 'proj-a',
      displayName: 'Alpha',
      topology: WorkspaceTopology.local,
    );
    final workspace = Workspace(
      workspaceId: 'proj-a',
      folders: const [WorkspaceFolder(path: '/remote', targetId: 'ssh:host')],
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
      topology: WorkspaceTopology.mixed,
    );
    expect(
      recentlyClosedTopology(entry: entry, workspace: null),
      WorkspaceTopology.mixed,
    );
  });
}
