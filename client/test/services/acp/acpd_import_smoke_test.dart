import 'package:acpd/acpd.dart' as acpd;
import 'package:acpd_test/acpd_test.dart' as acpd_test;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('acpd resolves from the vendored submodule', () {
    // Touch one exported symbol from each vendored package; the point is the
    // import path resolving to the pinned submodule, not the symbols.
    expect(acpd.ProtocolVersion.v1.value, 1);
  });

  test('acpd_test resolves from the vendored submodule', () {
    expect(acpd_test.MemoryTransportPair, isNotNull);
  });
}
