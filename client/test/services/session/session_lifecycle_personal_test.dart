import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';

class _Svc extends SessionLifecycleService {
  _Svc() : super(appDataBasePath: Directory.systemTemp.path);
  bool personalFor(Workspace p, AppSession s) =>
      debugIsPersonalLaunch(p, s);
}

void main() {
  final workspace = Workspace(
    workspaceId: 'p1',
    primaryPath: '/tmp/repo',
    createdAt: 0,
  );

  test('empty sessionTeam => personal launch', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'p1',
      primaryPath: '/tmp/repo',
      sessionTeam: '',
      createdAt: 0,
    );
    expect(_Svc().personalFor(workspace, session), isTrue);
  });

  test('non-empty sessionTeam => team launch', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'p1',
      primaryPath: '/tmp/repo',
      sessionTeam: 'team-x',
      createdAt: 0,
    );
    expect(_Svc().personalFor(workspace, session), isFalse);
  });
}
