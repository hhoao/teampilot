import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/launch/connect/launch_generation_store.dart';

void main() {
  test('bump starts at 1 and increments per session', () {
    final store = LaunchGenerationStore();

    expect(store.current('sess-a'), 0);
    expect(store.bump('sess-a'), 1);
    expect(store.bump('sess-a'), 2);
    expect(store.bump('sess-b'), 1);
    expect(store.current('sess-a'), 2);
  });

  test('matches only the current generation', () {
    final store = LaunchGenerationStore();
    store.bump('sess-1');

    expect(store.matches('sess-1', 1), isTrue);
    expect(store.matches('sess-1', 0), isFalse);

    store.bump('sess-1');
    expect(store.matches('sess-1', 1), isFalse);
    expect(store.matches('sess-1', 2), isTrue);
  });

  test('drop forgets the session clock', () {
    final store = LaunchGenerationStore();
    store.bump('sess-1');
    store.drop('sess-1');

    expect(store.current('sess-1'), 0);
    expect(store.matches('sess-1', 1), isFalse);
  });
}
