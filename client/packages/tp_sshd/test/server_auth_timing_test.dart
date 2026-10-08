@TestOn('vm')
library;

import 'dart:async';

import 'package:dartssh2/protocol.dart';
import 'package:test/test.dart';

import 'dual_test_utils.dart';

/// F1 (E01): the auth-failure reply must be padded out to a floor measured
/// from the request's receipt, so a timing peer cannot distinguish failure
/// classes (wrong-key vs unknown-user vs malformed-blob — sshd's
/// ensure_minimum_time_since anti-oracle).
///
/// The statistical acceptance (fresh-connection medians indistinguishable)
/// belongs to the differential harness's area E regeneration; these tests
/// pin the floor mechanism itself: the failure reply is not sent before the
/// floor has elapsed, per request.
void main() {
  test('a failed auth attempt waits out the floor before replying', () async {
    const floor = Duration(milliseconds: 150);
    var sentAt = DateTime.now();
    DateTime? failureAt;
    final (server, client) = await startRawPair(
      authenticate: (_) async => false,
      authFailureMinDelay: floor,
      onReady: (client) {
        client.sendPacket(SSH_Message_Service_Request('ssh-userauth').encode());
        sentAt = DateTime.now();
        client.sendPacket(testProbeRequest().encode());
      },
      onServerMessage: (payload) {
        if (SSHMessage.readMessageId(payload) ==
            SSH_Message_Userauth_Failure.messageId) {
          failureAt = DateTime.now();
        }
        return true;
      },
    );
    // Fails on timeout when the USERAUTH_FAILURE reply never arrives.
    await waitUntil(() => failureAt != null);
    // The server pads from its receipt of the request, which cannot precede
    // the client's send — so the client-side elapsed time is at least the
    // floor. Without the floor the reply lands in ~1 ms.
    expect(failureAt!.difference(sentAt), greaterThanOrEqualTo(floor));
    await server.close();
    client.close();
  });

  test('the floor is measured per request, not per connection', () async {
    const floor = Duration(milliseconds: 150);
    var sentAt = DateTime.now();
    var failures = 0;
    final secondFailure = Completer<void>();
    final (server, client) = await startRawPair(
      authenticate: (_) async => false,
      authFailureMinDelay: floor,
      onReady: (client) {
        client.sendPacket(SSH_Message_Service_Request('ssh-userauth').encode());
        sentAt = DateTime.now();
        client.sendPacket(testProbeRequest().encode());
      },
      onServerMessage: (payload) {
        if (SSHMessage.readMessageId(payload) ==
            SSH_Message_Userauth_Failure.messageId) {
          failures += 1;
          if (failures == 2) {
            secondFailure.complete();
          }
        }
        return true;
      },
    );
    await waitUntil(() => failures == 1);
    // A second attempt on the same connection must wait out its own floor
    // measured from its own receipt: if the floor were anchored to the
    // connection (or to the first request), this reply would land almost
    // immediately after its send.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    sentAt = DateTime.now();
    client.sendPacket(testProbeRequest().encode());
    await secondFailure.future.timeout(const Duration(seconds: 5));
    expect(DateTime.now().difference(sentAt), greaterThanOrEqualTo(floor));
    await server.close();
    client.close();
  });
}
