import 'package:acp_proxy/acp_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('timeouts are 30 minutes idle and 24 hours permission', () {
    expect(acpProxyIdleTimeout, const Duration(minutes: 30));
    expect(acpProxyPermissionTimeout, const Duration(hours: 24));
  });

  test(
    'idle timer runs only when the phone is gone and nothing is pending',
    () {
      expect(
        shouldRunIdleTimer(
          phoneConnected: false,
          turnInProgress: false,
          permissionPending: false,
        ),
        isTrue,
      );

      const others = <(bool, bool, bool)>[
        (false, false, true),
        (false, true, false),
        (false, true, true),
        (true, false, false),
        (true, false, true),
        (true, true, false),
        (true, true, true),
      ];
      for (final (phoneConnected, turnInProgress, permissionPending)
          in others) {
        expect(
          shouldRunIdleTimer(
            phoneConnected: phoneConnected,
            turnInProgress: turnInProgress,
            permissionPending: permissionPending,
          ),
          isFalse,
          reason:
              'phoneConnected=$phoneConnected '
              'turnInProgress=$turnInProgress '
              'permissionPending=$permissionPending',
        );
      }
    },
  );
}
