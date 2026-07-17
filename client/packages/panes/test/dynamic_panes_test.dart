import 'package:flutter_test/flutter_test.dart';
import 'package:panes/panes.dart';

void main() {
  group('PaneController Dynamic Management', () {
    test('addPane adds a new entry and notifies listeners', () {
      final controller = PaneController(entries: [
        PaneEntry(id: '1', initialSize: PaneSize.pixel(100)),
      ]);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      final newEntry = PaneEntry(id: '2', initialSize: PaneSize.pixel(200));
      controller.addPane(newEntry);

      expect(controller.entries.length, 2);
      expect(controller.entries[1].id, '2');
      expect(notifyCount, 1);
    });

    test('addPane at specific index', () {
      final controller = PaneController(entries: [
        PaneEntry(id: '1', initialSize: PaneSize.pixel(100)),
        PaneEntry(id: '3', initialSize: PaneSize.pixel(300)),
      ]);

      final newEntry = PaneEntry(id: '2', initialSize: PaneSize.pixel(200));
      controller.addPane(newEntry, index: 1);

      expect(controller.entries[1].id, '2');
      expect(controller.entries[2].id, '3');
    });

    test('removePane removes entry and cleans up state', () {
      final controller = PaneController(entries: [
        PaneEntry(id: '1', initialSize: PaneSize.pixel(100)),
      ]);

      controller.updateSize('1', PaneSize.pixel(150));
      controller.hide('1');

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.removePane('1');

      expect(controller.entries.isEmpty, true);
      expect(notifyCount, 1);

      // Verify state cleanup (internal maps)
      expect(controller.getVisualPixelSize('1'), null);
      expect(() => controller.isVisible('1'), throwsA(isA<Exception>()));
    });

    test('updatePane replaces existing entry', () {
      final controller = PaneController(entries: [
        PaneEntry(
            id: '1',
            initialSize: PaneSize.pixel(100),
            minSize: PaneSize.pixel(50)),
      ]);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      final updatedEntry = PaneEntry(
        id: '1',
        initialSize: PaneSize.pixel(100),
        minSize: PaneSize.pixel(80), // Changed minSize
      );
      controller.updatePane(updatedEntry);

      expect(controller.entries[0].minSize, PaneSize.pixel(80));
      expect(notifyCount, 1);
    });

    test('addPane throws if ID already exists', () {
      final controller = PaneController(entries: [
        PaneEntry(id: '1', initialSize: PaneSize.pixel(100)),
      ]);

      expect(
        () => controller
            .addPane(PaneEntry(id: '1', initialSize: PaneSize.pixel(200))),
        throwsArgumentError,
      );
    });
  });
}
