import 'package:test/test.dart';
import 'package:teampilot_scheduler/teampilot_scheduler.dart';

void main() {
  test('SessionInitException carries stage and path', () {
    final e = SessionInitException(
      SessionInitStage.project,
      path: '/work/a',
      message: 'cannot project',
    );
    expect(e.stage, SessionInitStage.project);
    expect(e.path, '/work/a');
    expect(e.toString(), contains('project'));
  });

  test('fullAccess policy defaults match client fullAccess', () {
    const p = SessionSecurityPolicy.fullAccess;
    expect(p.approval, SessionApprovalPolicy.never);
    expect(p.sandbox, SessionSandboxPolicy.fullAccess);
    expect(p.hookTrust, SessionHookTrustPolicy.bypass);
  });
}
