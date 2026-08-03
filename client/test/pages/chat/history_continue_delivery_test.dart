import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';

void main() {
  group('resolveHistoryContinueChannel', () {
    test('no bus always uses pty', () {
      expect(
        resolveHistoryContinueChannel(
          teamBusInstalled: false,
          memberWaitingForMessage: true,
          memberInTurn: true,
        ),
        HistoryContinueChannel.pty,
      );
    });

    test('bus + waiting uses mailbox', () {
      expect(
        resolveHistoryContinueChannel(
          teamBusInstalled: true,
          memberWaitingForMessage: true,
          memberInTurn: false,
        ),
        HistoryContinueChannel.mailbox,
      );
    });

    test('bus + inTurn uses mailbox', () {
      expect(
        resolveHistoryContinueChannel(
          teamBusInstalled: true,
          memberWaitingForMessage: false,
          memberInTurn: true,
        ),
        HistoryContinueChannel.mailbox,
      );
    });

    test('bus + idle uses pty', () {
      expect(
        resolveHistoryContinueChannel(
          teamBusInstalled: true,
          memberWaitingForMessage: false,
          memberInTurn: false,
        ),
        HistoryContinueChannel.pty,
      );
    });
  });

  group('shouldStartLiveRefreshOnContinueSuccess', () {
    test('pty continue attaches transcript live refresh', () {
      expect(
        shouldStartLiveRefreshOnContinueSuccess(HistoryContinueChannel.pty),
        isTrue,
      );
    });

    test(
      'mailbox continue also attaches live refresh for assistant transcript',
      () {
        expect(
          shouldStartLiveRefreshOnContinueSuccess(
            HistoryContinueChannel.mailbox,
          ),
          isTrue,
        );
      },
    );
  });
}
