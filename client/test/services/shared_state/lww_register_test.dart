import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/shared_state/hlc.dart';
import 'package:teampilot/services/shared_state/lww_register.dart';

void main() {
  const older = Hlc(wallMillis: 1, counter: 0, nodeId: 'a');
  const newer = Hlc(wallMillis: 2, counter: 0, nodeId: 'a');

  test('merge keeps the greater stamp in both directions', () {
    final a = const LwwRegister<String>(value: 'a', stamp: older);
    final b = const LwwRegister<String>(value: 'b', stamp: newer);

    expect(a.merge(b).value, 'b');
    expect(b.merge(a).value, 'b');
  });

  test('equal stamps keep the local value', () {
    const stamp = Hlc(wallMillis: 1, counter: 1, nodeId: 'a');
    final a = const LwwRegister<String>(value: 'a', stamp: stamp);
    final b = const LwwRegister<String>(value: 'b', stamp: stamp);

    expect(a.merge(b).value, 'a');
    expect(b.merge(a).value, 'b');
  });

  test('json round-trips through a value codec', () {
    final register = const LwwRegister<String>(value: 'x', stamp: newer);
    final decoded = LwwRegister.fromJson<String>(
      register.toJson((value) => value),
      decode: (value) => value! as String,
    );

    expect(decoded?.value, 'x');
    expect(decoded?.stamp.toWire(), newer.toWire());
  });
}
