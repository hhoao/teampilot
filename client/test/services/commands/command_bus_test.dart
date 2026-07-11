import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_bus.dart';

void main() {
  group('CommandBus', () {
    test('register then invoke calls the handler', () {
      var callCount = 0;
      final bus = CommandBus();
      bus.register('test.command', () => callCount++);

      bus.invoke('test.command');

      expect(callCount, 1);
    });

    test('invoke with no registered handler is a silent no-op', () {
      final bus = CommandBus();

      expect(() => bus.invoke('missing.command'), returnsNormally);
    });

    test('unregister removes the handler so invoke no-ops', () {
      var callCount = 0;
      final bus = CommandBus();
      bus.register('test.command', () => callCount++);

      bus.unregister('test.command');
      bus.invoke('test.command');

      expect(callCount, 0);
    });

    test('unregister with a matching handler removes it', () {
      var callCount = 0;
      void handler() => callCount++;
      final bus = CommandBus();
      bus.register('test.command', handler);

      bus.unregister('test.command', handler);
      bus.invoke('test.command');

      expect(callCount, 0);
    });

    test('unregister with a stale handler does not clobber a newer one', () {
      var firstCalled = false;
      var secondCalled = false;
      void firstHandler() => firstCalled = true;
      void secondHandler() => secondCalled = true;
      final bus = CommandBus();
      bus.register('test.command', firstHandler);
      bus.register('test.command', secondHandler);

      bus.unregister('test.command', firstHandler);
      bus.invoke('test.command');

      expect(firstCalled, isFalse);
      expect(secondCalled, isTrue);
    });

    test('re-register replaces the previous handler', () {
      var firstCalled = false;
      var secondCalled = false;
      final bus = CommandBus();
      bus.register('test.command', () => firstCalled = true);
      bus.register('test.command', () => secondCalled = true);

      bus.invoke('test.command');

      expect(firstCalled, isFalse);
      expect(secondCalled, isTrue);
    });
  });
}
