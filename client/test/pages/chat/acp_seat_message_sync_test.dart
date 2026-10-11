import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/pages/chat/acp_seat_message_sync.dart';

void main() {
  test('empty launching cubit does not wipe an existing seat', () {
    expect(
      shouldPublishAcpSeatMessages(
        cubitMessages: const [],
        phase: AcpChatPhase.launching,
        seatHasMessages: true,
        historyHydrated: false,
      ),
      isFalse,
    );
  });

  test('unhydrated empty cubit stays on the history loading pane', () {
    expect(
      shouldShowAcpHistoryLoading(
        cubitMessages: const [],
        historyHydrated: false,
      ),
      isTrue,
    );
    expect(
      shouldPublishAcpSeatMessages(
        cubitMessages: const [],
        phase: AcpChatPhase.launching,
        seatHasMessages: false,
        historyHydrated: false,
      ),
      isFalse,
    );
  });

  test('hydrated empty cubit may publish the empty-history pane', () {
    expect(
      shouldShowAcpHistoryLoading(
        cubitMessages: const [],
        historyHydrated: true,
      ),
      isFalse,
    );
    expect(
      shouldPublishAcpSeatMessages(
        cubitMessages: const [],
        phase: AcpChatPhase.launching,
        seatHasMessages: false,
        historyHydrated: true,
      ),
      isTrue,
    );
  });

  test('ready cubit messages replace the seat even when empty', () {
    expect(
      shouldPublishAcpSeatMessages(
        cubitMessages: const [],
        phase: AcpChatPhase.ready,
        seatHasMessages: true,
        historyHydrated: true,
      ),
      isTrue,
    );
  });

  test('non-empty launching cubit publishes the user bubble', () {
    expect(
      shouldPublishAcpSeatMessages(
        cubitMessages: [
          AiMessage(
            id: 'u1',
            role: AiRole.user,
            parts: const [AiTextPart(text: 'hello')],
            createdAt: DateTime(2026),
          ),
        ],
        phase: AcpChatPhase.launching,
        seatHasMessages: true,
        historyHydrated: false,
      ),
      isTrue,
    );
    expect(
      shouldShowAcpHistoryLoading(
        cubitMessages: [
          AiMessage(
            id: 'u1',
            role: AiRole.user,
            parts: const [AiTextPart(text: 'hello')],
            createdAt: DateTime(2026),
          ),
        ],
        historyHydrated: false,
      ),
      isFalse,
    );
  });
}
