import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_job_scope.dart';
import 'package:teampilot/services/install/install_job_keys.dart';

void main() {
  test('adapter install keys are target-scoped, not Claude/Codex-only', () {
    const scope = InstallJobScopeLocal();
    final key = InstallJobKeys.acpAdapter(
      'adapter:antigravity-acp',
      scope: scope,
    );
    expect(key.target, 'adapter:antigravity-acp');
    expect(key, isNot(InstallJobKeys.claudeAcpAdapter(scope: scope)));
  });
}
