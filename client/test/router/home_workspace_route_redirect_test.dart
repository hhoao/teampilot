import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/router/app_router.dart';

void main() {
  group('homeWorkspaceRouteRedirect', () {
    test('keeps a workspace that exists in the current home index', () {
      expect(
        homeWorkspaceRouteRedirect(
          workspaceId: 'ws-1',
          workspaceIds: const ['ws-2', 'ws-1'],
        ),
        isNull,
      );
    });

    test('falls back to home when the id belongs to another home', () {
      // Device-local lastOpenedWorkspaceId survives a home switch, so the
      // restored workspace id may not exist in the replacement plane's index.
      expect(
        homeWorkspaceRouteRedirect(
          workspaceId: 'ws-from-old-home',
          workspaceIds: const ['ws-2'],
        ),
        '/home-v2',
      );
    });

    test('falls back to home for an empty or missing id', () {
      expect(
        homeWorkspaceRouteRedirect(workspaceId: null, workspaceIds: const []),
        '/home-v2',
      );
      expect(
        homeWorkspaceRouteRedirect(workspaceId: '   ', workspaceIds: const []),
        '/home-v2',
      );
    });
  });
}
