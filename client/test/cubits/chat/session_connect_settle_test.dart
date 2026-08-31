import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/session_connect_settle.dart';

void main() {
  test('awaitSessionConnectSettle returns once isConnecting is false', () async {
    var connecting = true;
    var polls = 0;
    await awaitSessionConnectSettle(
      isConnecting: () => connecting,
      isClosed: () => false,
      pollInterval: const Duration(milliseconds: 1),
      delay: (_) async {
        polls++;
        if (polls >= 2) connecting = false;
      },
    );
    expect(polls, 2);
    expect(connecting, isFalse);
  });

  test('awaitSessionConnectSettle stops when closed', () async {
    var polls = 0;
    await awaitSessionConnectSettle(
      isConnecting: () => true,
      isClosed: () => polls >= 1,
      pollInterval: const Duration(milliseconds: 1),
      delay: (_) async {
        polls++;
      },
    );
    expect(polls, 1);
  });

  test('awaitSessionConnectSettle stops at timeout', () async {
    var now = DateTime.utc(2026, 1, 1);
    var polls = 0;
    await awaitSessionConnectSettle(
      isConnecting: () => true,
      isClosed: () => false,
      pollInterval: const Duration(milliseconds: 10),
      timeout: const Duration(milliseconds: 25),
      clock: () => now,
      delay: (d) async {
        polls++;
        now = now.add(d);
      },
    );
    expect(polls, greaterThanOrEqualTo(2));
    expect(polls, lessThan(10));
  });
}
