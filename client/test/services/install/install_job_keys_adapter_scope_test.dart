import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_job_scope.dart';
import 'package:teampilot/services/install/install_job_keys.dart';

void main() {
  test('adapter keys default to local scope and differ per profile', () {
    final local = InstallJobKeys.claudeAcpAdapter();
    expect(local.scope, const InstallJobScopeLocal());

    final a = InstallJobKeys.claudeAcpAdapter(
      scope: const InstallJobScopeSsh('p1'),
    );
    final b = InstallJobKeys.claudeAcpAdapter(
      scope: const InstallJobScopeSsh('p2'),
    );
    expect(a == b, isFalse);
    expect(a == local, isFalse);
    expect(
      InstallJobKeys.codexAcpAdapter(scope: const InstallJobScopeSsh('p1')),
      isNot(
        InstallJobKeys.claudeAcpAdapter(
          scope: const InstallJobScopeSsh('p1'),
        ),
      ),
    );
  });
}
