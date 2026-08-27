import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_route.dart';

void main() {
  group('HomeWorkspaceRoute.session', () {
    test('decodes session query param', () {
      expect(
        HomeWorkspaceRoute.session('/home-v2/workspace/ws-1?session=sess-42'),
        'sess-42',
      );
      expect(
        HomeWorkspaceRoute.session(
          '/home-v2/workspace/ws-1?profile=personal&session=sess-42',
        ),
        'sess-42',
      );
      expect(HomeWorkspaceRoute.session('/home-v2/workspace/ws-1'), isNull);
      expect(
        HomeWorkspaceRoute.session('/home-v2/workspace/ws-1?session='),
        isNull,
      );
    });
  });

  group('HomeWorkspaceRoute.sessionLocation', () {
    test('builds workspace session deep link', () {
      expect(
        HomeWorkspaceRoute.sessionLocation(
          workspaceId: 'ws-1',
          sessionId: 'sess-42',
        ),
        '/home-v2/workspace/ws-1?session=sess-42',
      );
    });
  });

  group('HomeWorkspaceRoute.locationWithoutSession', () {
    test('strips session and keeps other query params', () {
      expect(
        HomeWorkspaceRoute.locationWithoutSession(
          '/home-v2/workspace/ws-1?session=sess-42',
        ),
        '/home-v2/workspace/ws-1',
      );
      expect(
        HomeWorkspaceRoute.locationWithoutSession(
          '/home-v2/workspace/ws-1?profile=p1&session=sess-42&view=manage',
        ),
        '/home-v2/workspace/ws-1?profile=p1&view=manage',
      );
      expect(
        HomeWorkspaceRoute.locationWithoutSession('/home-v2/workspace/ws-1'),
        '/home-v2/workspace/ws-1',
      );
    });
  });

  group('HomeWorkspaceRoute.locationWithoutManage', () {
    test('strips manage view and section, keeps profile', () {
      expect(
        HomeWorkspaceRoute.locationWithoutManage(
          '/home-v2/workspace/ws-1?profile=p1&view=manage&section=settings',
        ),
        '/home-v2/workspace/ws-1?profile=p1',
      );
      expect(
        HomeWorkspaceRoute.locationWithoutManage(
          '/home-v2/workspace/ws-1?view=manage',
        ),
        '/home-v2/workspace/ws-1',
      );
      expect(
        HomeWorkspaceRoute.locationWithoutManage(
          '/home-v2/workspace/ws-1?profile=p1',
        ),
        '/home-v2/workspace/ws-1?profile=p1',
      );
    });
  });
}
