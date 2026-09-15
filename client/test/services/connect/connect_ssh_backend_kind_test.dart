@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/connect_ssh_backend.dart';

void main() {
  test('parseConnectSshBackendKind treats only the system token as system', () {
    expect(parseConnectSshBackendKind('system'), ConnectSshBackendKind.system);
    expect(parseConnectSshBackendKind('embedded'), ConnectSshBackendKind.embedded);
    expect(parseConnectSshBackendKind(null), ConnectSshBackendKind.embedded);
    expect(parseConnectSshBackendKind(''), ConnectSshBackendKind.embedded);
    expect(parseConnectSshBackendKind('SYSTEM'), ConnectSshBackendKind.embedded);
    expect(parseConnectSshBackendKind(1), ConnectSshBackendKind.embedded);
  });

  test('effectiveConnectSshBackend ignores system unless selectable', () {
    expect(
      effectiveConnectSshBackend(
        stored: ConnectSshBackendKind.system,
        systemSshdSelectable: true,
      ),
      ConnectSshBackendKind.system,
    );
    expect(
      effectiveConnectSshBackend(
        stored: ConnectSshBackendKind.system,
        systemSshdSelectable: false,
      ),
      ConnectSshBackendKind.embedded,
    );
    expect(
      effectiveConnectSshBackend(
        stored: ConnectSshBackendKind.embedded,
        systemSshdSelectable: true,
      ),
      ConnectSshBackendKind.embedded,
    );
  });
}
