import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/ssh_transport_close.dart';
import 'package:teampilot/services/ssh/ssh_transport_close_policy.dart';

void main() {
  group('SshTransportClosePolicy', () {
    test('memberSessionClosed does not affect durable home', () {
      final d = SshTransportClosePolicy.evaluate(
        const SshTransportClosed(
          reason: SshTransportCloseReason.memberSessionClosed,
          plane: SshTransportPlane.member,
        ),
      );
      expect(d.affectsDurableHome, isFalse);
      expect(d.emitDisconnectNotification, isFalse);
      expect(d.scheduleStorageReconnect, isFalse);
    });

    test('expected local member closes do not affect durable home', () {
      for (final reason in [
        SshTransportCloseReason.userDisconnect,
        SshTransportCloseReason.profileInvalidated,
        SshTransportCloseReason.profileRemoved,
        SshTransportCloseReason.runtimeContextEvicted,
        SshTransportCloseReason.disconnectAll,
        SshTransportCloseReason.remoteFileStoreDisconnect,
      ]) {
        final d = SshTransportClosePolicy.evaluate(
          SshTransportClosed(reason: reason, plane: SshTransportPlane.member),
        );
        expect(d.affectsDurableHome, isFalse, reason: reason.name);
      }
    });

    test('unexpected member closes affect durable home and schedule reconnect', () {
      for (final reason in [
        SshTransportCloseReason.remotePeerClosed,
        SshTransportCloseReason.transportError,
      ]) {
        final d = SshTransportClosePolicy.evaluate(
          SshTransportClosed(reason: reason, plane: SshTransportPlane.member),
        );
        expect(d.affectsDurableHome, isTrue, reason: reason.name);
        expect(d.emitDisconnectNotification, isTrue, reason: reason.name);
        expect(d.scheduleStorageReconnect, isTrue, reason: reason.name);
      }
    });

    test('unexpected storage closes affect durable home', () {
      final d = SshTransportClosePolicy.evaluate(
        const SshTransportClosed(
          reason: SshTransportCloseReason.remotePeerClosed,
          plane: SshTransportPlane.storage,
        ),
      );
      expect(d.affectsDurableHome, isTrue);
      expect(d.scheduleStorageReconnect, isTrue);
    });

    test('expected local storage closes mark durable home but skip auto-reconnect', () {
      final d = SshTransportClosePolicy.evaluate(
        const SshTransportClosed(
          reason: SshTransportCloseReason.userDisconnect,
          plane: SshTransportPlane.storage,
        ),
      );
      expect(d.affectsDurableHome, isTrue);
      expect(d.emitDisconnectNotification, isTrue);
      expect(d.scheduleStorageReconnect, isFalse);
    });

    test('fromError maps SshTransportClosed passthrough', () {
      const closed = SshTransportClosed(
        reason: SshTransportCloseReason.memberSessionClosed,
        plane: SshTransportPlane.member,
      );
      expect(
        SshTransportClosePolicy.evaluateError(closed).affectsDurableHome,
        isFalse,
      );
    });

    test('fromError treats unknown errors as durable storage-affecting', () {
      final d = SshTransportClosePolicy.evaluateError(StateError('boom'));
      expect(d.affectsDurableHome, isTrue);
      expect(d.scheduleStorageReconnect, isTrue);
    });
  });
}
