import 'package:acp_proxy/acp_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('empty requested env values unset the parent variable', () {
    final merged = mergeAcpProxyProcessEnvironment(
      const {'KEEP': 'yes', 'DROP': ''},
      parent: const {'KEEP': 'old', 'DROP': 'secret', 'OTHER': '1'},
    );

    expect(merged['KEEP'], 'yes');
    expect(merged['OTHER'], '1');
    expect(merged.containsKey('DROP'), isFalse);
    expect(merged.values, isNot(contains('secret')));
  });
}
