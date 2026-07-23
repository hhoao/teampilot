import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/resource_manager/pty_process_registry.dart';

void main() {
  test('register and list by bindingKey', () {
    final r = PtyProcessRegistry();
    r.register(bindingKey: 'chat:s1:m1', pid: 42);
    expect(r.pidFor('chat:s1:m1'), 42);
    expect(r.entries, hasLength(1));
  });

  test('unregister removes entry', () {
    final r = PtyProcessRegistry();
    r.register(bindingKey: 'chat:s1:m1', pid: 42);
    r.unregister('chat:s1:m1');
    expect(r.pidFor('chat:s1:m1'), isNull);
    expect(r.entries, isEmpty);
  });

  test('register with null pid is a no-op', () {
    final r = PtyProcessRegistry();
    r.register(bindingKey: 'chat:s1:m1', pid: null);
    expect(r.pidFor('chat:s1:m1'), isNull);
    expect(r.entries, isEmpty);

    r.register(bindingKey: 'chat:s1:m1', pid: 42);
    r.register(bindingKey: 'chat:s1:m1', pid: null);
    expect(r.pidFor('chat:s1:m1'), 42);
    expect(r.entries, hasLength(1));
  });
}
