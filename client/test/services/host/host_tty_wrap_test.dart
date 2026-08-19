import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_run_request.dart';
import 'package:teampilot/services/host/host_tty_wrap.dart';

void main() {
  test('gnu script wrap keeps env and quotes login argv', () {
    const request = HostRunRequest(
      executable: 'codex',
      arguments: ['login', '--device-auth'],
      environment: {'CODEX_HOME': '/tmp/codex home'},
      pathPrepend: ['/tmp/node/bin'],
      allocateTty: true,
    );

    final wrapped = HostTtyWrap.apply(request, flavor: HostTtyScriptFlavor.gnu);

    expect(wrapped.executable, 'script');
    expect(wrapped.arguments, [
      '-qefc',
      "'codex' 'login' '--device-auth'",
      '/dev/null',
    ]);
    expect(wrapped.environment, request.environment);
    expect(wrapped.pathPrepend, request.pathPrepend);
  });

  test('does not wrap when allocateTty is false', () {
    const request = HostRunRequest(executable: 'codex');
    expect(
      HostTtyWrap.apply(request, flavor: HostTtyScriptFlavor.gnu),
      same(request),
    );
  });
}
