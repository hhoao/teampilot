import 'package:flutter_test/flutter_test.dart';
import 'package:panes/panes.dart';

void main() {
  test('PaneController visibility toggle cycle', () {
    final controller = PaneController(
      entries: [
        PaneEntry(id: '1', initialSize: PaneSize.pixel(100)),
      ],
    );

    expect(controller.isVisible('1'), isTrue);
    controller.toggle('1');
    expect(controller.isVisible('1'), isFalse);
    controller.toggle('1');
    expect(controller.isVisible('1'), isTrue);
  });

  test('PaneController maximize/restore cycle', () {
    final controller = PaneController(
      entries: [
        PaneEntry(id: '1', initialSize: PaneSize.pixel(100)),
        PaneEntry(id: '2', initialSize: PaneSize.pixel(100)),
      ],
    );

    expect(controller.isMaximized, isFalse);
    controller.maximize('1');
    expect(controller.isMaximized, isTrue);
    expect(controller.maximizedPaneId, '1');
    controller.restore();
    expect(controller.isMaximized, isFalse);
  });

  test('PaneController save/load preserves state', () {
    final controller = PaneController(
      entries: [
        PaneEntry(id: '1', initialSize: PaneSize.pixel(100)),
        PaneEntry(id: '2', initialSize: PaneSize.fraction(1.0)),
      ],
    );

    controller.updateSize('1', PaneSize.pixel(150));
    controller.hide('1');
    final data = controller.save();

    final newController = PaneController(
      entries: [
        PaneEntry(id: '1', initialSize: PaneSize.pixel(100)),
        PaneEntry(id: '2', initialSize: PaneSize.fraction(1.0)),
      ],
    );
    newController.load(data);

    expect(newController.getPixelSize('1'), 150);
    expect(newController.isVisible('1'), isFalse);
  });
}
