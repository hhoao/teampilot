import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/termux/termux_connection_gate.dart';

void main() {
  test('session launch choke uses termuxWorkOpsBlockMessage for termux target', () {
    const message = 'termux disconnected';
    expect(
      termuxWorkOpsBlockMessage(
        target: RuntimeTarget.termux(),
        home: RuntimeTarget.termux(),
        termuxConnected: false,
        message: message,
      ),
      message,
    );
    expect(
      termuxWorkOpsBlockMessage(
        target: RuntimeTarget.termux(),
        home: RuntimeTarget.termux(),
        termuxConnected: true,
        message: message,
      ),
      isNull,
    );
  });
}
