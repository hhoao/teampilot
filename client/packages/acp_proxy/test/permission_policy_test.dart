import 'package:acp_proxy/acp_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('fullAccess auto-allows and ask holds', () {
    expect(
      permissionActionWhenDisconnected(AcpProxyPermissionPolicy.fullAccess),
      DisconnectedPermissionAction.autoAllow,
    );
    expect(
      permissionActionWhenDisconnected(AcpProxyPermissionPolicy.ask),
      DisconnectedPermissionAction.hold,
    );
  });

  test('prefers allow-always over allow-once', () {
    final id = preferredAllowOptionId([
      {'optionId': 'once', 'kind': 'allow-once'},
      {'optionId': 'always', 'kind': 'allow-always'},
      {'optionId': 'no', 'kind': 'reject-once'},
    ]);
    expect(id, 'always');
  });

  test('returns null when every option rejects', () {
    expect(
      preferredAllowOptionId([
        {'optionId': 'no', 'kind': 'reject_once'},
      ]),
      isNull,
    );
  });
}
