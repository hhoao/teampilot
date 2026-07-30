import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/termux/apply_termux_connect_home.dart';

void main() {
  test('applyTermuxConnectHome selects termux:default', () async {
    final calls = <String>[];
    await applyTermuxConnectHome(
      selectHome: (id) async => calls.add('home:$id'),
    );
    expect(calls, ['home:${RuntimeTarget.termuxDefaultId}']);
  });

  test('applyTermuxClearSetupHome selects local', () async {
    final calls = <String>[];
    await applyTermuxClearSetupHome(
      selectHome: (id) async => calls.add('home:$id'),
    );
    expect(calls, ['home:${RuntimeTarget.localId}']);
  });
}
