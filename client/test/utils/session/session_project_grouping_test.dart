import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/git_worktree.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/utils/session/app_session_sort.dart';
import 'package:teampilot/utils/session/session_project_grouping.dart';

void main() {
  group('groupSessionsByWorktreeAcrossProjects', () {
    test('flattens projects into worktree groups with sessions', () {
      const folders = [
        WorkspaceFolder(path: '/repo-a'),
        WorkspaceFolder(path: '/repo-b'),
      ];
      final worktreesByProject = {
        '/repo-a': [
          GitWorktree(
            path: '/repo-a',
            branch: 'refs/heads/main',
            head: 'a',
            isBare: false,
            isMainWorktree: true,
          ),
          GitWorktree(
            path: '/repo-a/.worktrees/feature',
            branch: 'refs/heads/feature',
            head: 'b',
            isBare: false,
            isMainWorktree: false,
          ),
        ],
        '/repo-b': [
          GitWorktree(
            path: '/repo-b',
            branch: 'refs/heads/main',
            head: 'c',
            isBare: false,
            isMainWorktree: true,
          ),
        ],
      };
      final sessions = [
        AppSession(
          sessionId: 's1',
          workspaceId: 'w1',
          folders: const [WorkspaceFolder(path: '/repo-a')],
          createdAt: 1,
        ),
        AppSession(
          sessionId: 's2',
          workspaceId: 'w1',
          folders: const [WorkspaceFolder(path: '/repo-a/.worktrees/feature')],
          createdAt: 1,
        ),
        AppSession(
          sessionId: 's3',
          workspaceId: 'w1',
          folders: const [WorkspaceFolder(path: '/repo-b')],
          createdAt: 1,
        ),
      ];

      final groups = groupSessionsByWorktreeAcrossProjects(
        folders: folders,
        worktreesByProjectPath: worktreesByProject,
        sessions: sessions,
      );

      expect(groups, hasLength(3));
      expect(groups[0].projectFolderPath, '/repo-a');
      expect(groups[0].sessions.map((s) => s.sessionId), ['s1']);
      expect(groups[1].projectFolderPath, '/repo-a');
      expect(groups[1].sessions.map((s) => s.sessionId), ['s2']);
      expect(groups[2].projectFolderPath, '/repo-b');
      expect(groups[2].sessions.map((s) => s.sessionId), ['s3']);
    });

    test('disambiguates duplicate branch names with project prefix', () {
      const folders = [
        WorkspaceFolder(path: '/repo-a'),
        WorkspaceFolder(path: '/repo-b'),
      ];
      final worktreesByProject = {
        '/repo-a': [
          GitWorktree(
            path: '/repo-a',
            branch: 'refs/heads/main',
            head: 'a',
            isBare: false,
            isMainWorktree: true,
          ),
        ],
        '/repo-b': [
          GitWorktree(
            path: '/repo-b',
            branch: 'refs/heads/main',
            head: 'b',
            isBare: false,
            isMainWorktree: true,
          ),
        ],
      };

      final groups = groupSessionsByWorktreeAcrossProjects(
        folders: folders,
        worktreesByProjectPath: worktreesByProject,
        sessions: const [],
      );

      expect(groups, hasLength(2));
      expect(groups[0].sidebarLabel, 'repo-a/main');
      expect(groups[1].sidebarLabel, 'repo-b/main');
    });

    test('keeps short branch when names are unique', () {
      const folders = [
        WorkspaceFolder(path: '/repo-a'),
        WorkspaceFolder(path: '/repo-b'),
      ];
      final worktreesByProject = {
        '/repo-a': [
          GitWorktree(
            path: '/repo-a',
            branch: 'refs/heads/main',
            head: 'a',
            isBare: false,
            isMainWorktree: true,
          ),
        ],
        '/repo-b': [
          GitWorktree(
            path: '/repo-b',
            branch: 'refs/heads/develop',
            head: 'b',
            isBare: false,
            isMainWorktree: true,
          ),
        ],
      };

      final groups = groupSessionsByWorktreeAcrossProjects(
        folders: folders,
        worktreesByProjectPath: worktreesByProject,
        sessions: const [],
      );

      expect(groups[0].sidebarLabel, isNull);
      expect(groups[1].sidebarLabel, isNull);
    });

    test('uses project groups for non-git folders', () {
      const folders = [
        WorkspaceFolder(path: '/plain-a'),
        WorkspaceFolder(path: '/repo-b'),
      ];
      final worktreesByProject = {
        '/repo-b': [
          GitWorktree(
            path: '/repo-b',
            branch: 'refs/heads/main',
            head: 'c',
            isBare: false,
            isMainWorktree: true,
          ),
        ],
      };
      final sessions = [
        AppSession(
          sessionId: 's1',
          workspaceId: 'w1',
          folders: const [WorkspaceFolder(path: '/plain-a')],
          createdAt: 1,
        ),
        AppSession(
          sessionId: 's2',
          workspaceId: 'w1',
          folders: const [WorkspaceFolder(path: '/repo-b')],
          createdAt: 1,
        ),
      ];

      final groups = groupSessionsByWorktreeAcrossProjects(
        folders: folders,
        worktreesByProjectPath: worktreesByProject,
        sessions: sessions,
      );

      expect(groups, hasLength(2));
      expect(groups[0].isProjectGroup, isTrue);
      expect(groups[0].projectFolderPath, '/plain-a');
      expect(groups[0].sessions.map((s) => s.sessionId), ['s1']);
      expect(groups[1].isProjectGroup, isFalse);
      expect(groups[1].worktree?.path, '/repo-b');
      expect(groups[1].sessions.map((s) => s.sessionId), ['s2']);
    });

    test(
      'app-managed worktree outside repo tree groups under owning project',
      () {
        const repo = '/home/hhoa/git/hhoa/teampilot';
        const parent = '/home/hhoa/git';
        const externalWt =
            '/home/hhoa/.local/share/com.hhoa.teampilot/worktrees/teampilot/feature/expert-hub';
        const folders = [
          WorkspaceFolder(path: repo),
          WorkspaceFolder(path: parent),
        ];
        final worktreesByProject = {
          repo: [
            GitWorktree(
              path: repo,
              branch: 'refs/heads/main',
              head: 'a',
              isBare: false,
              isMainWorktree: true,
            ),
            GitWorktree(
              path: externalWt,
              branch: 'refs/heads/feature/expert-hub',
              head: 'b',
              isBare: false,
              isMainWorktree: false,
            ),
          ],
          parent: const <GitWorktree>[],
        };
        final sessions = [
          AppSession(
            sessionId: 's-expert',
            workspaceId: 'w1',
            folders: const [
              WorkspaceFolder(path: externalWt),
              WorkspaceFolder(path: repo),
              WorkspaceFolder(path: parent),
            ],
            createdAt: 1,
          ),
        ];

        final groups = groupSessionsByWorktreeAcrossProjects(
          folders: folders,
          worktreesByProjectPath: worktreesByProject,
          sessions: sessions,
        );

        final expertGroup = groups.firstWhere(
          (g) => g.worktree?.path == externalWt,
        );
        expect(expertGroup.projectFolderPath, repo);
        expect(expertGroup.sessions.map((s) => s.sessionId), ['s-expert']);
        expect(groups.any((g) => g.isOrphan), isFalse);
      },
    );

    test('nested workspace folders assign each session to the deepest match', () {
      const folders = [
        WorkspaceFolder(path: '/home/hhoa/git'),
        WorkspaceFolder(path: '/home/hhoa/git/teampilot'),
      ];
      final worktreesByProject = <String, List<GitWorktree>>{
        '/home/hhoa/git': const [],
        '/home/hhoa/git/teampilot': [
          GitWorktree(
            path: '/home/hhoa/git/teampilot',
            branch: 'refs/heads/main',
            head: 'a',
            isBare: false,
            isMainWorktree: true,
          ),
        ],
      };
      final sessions = [
        AppSession(
          sessionId: 's-main',
          workspaceId: 'w1',
          folders: const [
            WorkspaceFolder(path: '/home/hhoa/git/teampilot'),
          ],
          createdAt: 1,
        ),
        AppSession(
          sessionId: 's-parent',
          workspaceId: 'w1',
          folders: const [WorkspaceFolder(path: '/home/hhoa/git')],
          createdAt: 1,
        ),
      ];

      final groups = groupSessionsByWorktreeAcrossProjects(
        folders: folders,
        worktreesByProjectPath: worktreesByProject,
        sessions: sessions,
      );

      final mainGroup = groups.firstWhere(
        (g) => g.worktree?.path == '/home/hhoa/git/teampilot',
      );
      final parentGroup = groups.firstWhere((g) => g.isProjectGroup);

      expect(mainGroup.sessions.map((s) => s.sessionId), ['s-main']);
      expect(parentGroup.projectFolderPath, '/home/hhoa/git');
      expect(parentGroup.sessions.map((s) => s.sessionId), ['s-parent']);
      expect(
        groups.expand((g) => g.sessions).map((s) => s.sessionId).toSet(),
        {'s-main', 's-parent'},
      );
    });

    test('preserves recentlyUpdated order within each project worktree group', () {
      const folders = [
        WorkspaceFolder(path: '/repo-a'),
        WorkspaceFolder(path: '/repo-b'),
      ];
      final worktreesByProject = {
        '/repo-a': [
          GitWorktree(
            path: '/repo-a',
            branch: 'refs/heads/main',
            head: 'a',
            isBare: false,
            isMainWorktree: true,
          ),
        ],
        '/repo-b': [
          GitWorktree(
            path: '/repo-b',
            branch: 'refs/heads/main',
            head: 'c',
            isBare: false,
            isMainWorktree: true,
          ),
        ],
      };
      final unsorted = [
        AppSession(
          sessionId: 'a-old',
          workspaceId: 'w',
          folders: const [WorkspaceFolder(path: '/repo-a')],
          createdAt: 1,
          updatedAt: 10,
        ),
        AppSession(
          sessionId: 'b-new',
          workspaceId: 'w',
          folders: const [WorkspaceFolder(path: '/repo-b')],
          createdAt: 1,
          updatedAt: 50,
        ),
        AppSession(
          sessionId: 'a-new',
          workspaceId: 'w',
          folders: const [WorkspaceFolder(path: '/repo-a')],
          createdAt: 1,
          updatedAt: 40,
        ),
        AppSession(
          sessionId: 'b-old',
          workspaceId: 'w',
          folders: const [WorkspaceFolder(path: '/repo-b')],
          createdAt: 1,
          updatedAt: 5,
        ),
      ];
      final sorted = sortAppSessions(
        unsorted,
        sort: AppSessionSort.recentlyUpdated,
      );
      final groups = groupSessionsByWorktreeAcrossProjects(
        folders: folders,
        worktreesByProjectPath: worktreesByProject,
        sessions: sorted,
      );

      final aMain = groups.firstWhere((g) => g.worktree?.path == '/repo-a');
      expect(
        [for (final s in aMain.sessions) s.sessionId],
        ['a-new', 'a-old'],
      );
      final bMain = groups.firstWhere((g) => g.worktree?.path == '/repo-b');
      expect(
        [for (final s in bMain.sessions) s.sessionId],
        ['b-new', 'b-old'],
      );
    });

    test('resolves archived sessions from an active-only worktree group', () {
      const folders = [WorkspaceFolder(path: '/repo')];
      final worktreesByProject = {
        '/repo': [
          const GitWorktree(
            path: '/repo',
            branch: 'refs/heads/main',
            head: 'a',
            isBare: false,
            isMainWorktree: true,
          ),
          const GitWorktree(
            path: '/worktrees/feature',
            branch: 'refs/heads/feature',
            head: 'b',
            isBare: false,
            isMainWorktree: false,
          ),
        ],
      };
      final active = AppSession(
        sessionId: 'active',
        workspaceId: 'w',
        folders: const [WorkspaceFolder(path: '/worktrees/feature')],
        createdAt: 1,
      );
      final archived = AppSession(
        sessionId: 'archived',
        workspaceId: 'w',
        folders: const [WorkspaceFolder(path: '/worktrees/feature/subdir')],
        createdAt: 1,
        archived: true,
      );
      final activeGroups = groupSessionsByWorktreeAcrossProjects(
        folders: folders,
        worktreesByProjectPath: worktreesByProject,
        sessions: [active],
      );
      final featureGroup = activeGroups.firstWhere(
        (group) => group.worktree?.path == '/worktrees/feature',
      );

      final resolved = unfilteredSessionsForWorktreeGroup(
        group: featureGroup,
        folders: folders,
        worktreesByProjectPath: worktreesByProject,
        sessions: [active, archived],
      );

      expect(resolved.map((session) => session.sessionId), [
        'active',
        'archived',
      ]);
    });
  });
}
