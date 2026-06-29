import 'package:flutter_test/flutter_test.dart';

import '../../../tool/performance_snapshot/dart_slice_analysis.dart';
import '../../../tool/performance_snapshot/precision_analysis.dart';

void main() {
  group('widgetMatchesSliceName', () {
    test('matches exact widget and generic-stripped names', () {
      expect(
        widgetMatchesSliceName('RightToolsPanel', 'RightToolsPanel'),
        isTrue,
      );
      expect(
        widgetMatchesSliceName(
          'BlocProvider<FileTreeCubit>',
          'BlocProvider<FileTreeCubit>',
        ),
        isTrue,
      );
      expect(
        widgetMatchesSliceName('BlocProvider<FileTreeCubit>', 'BlocProvider'),
        isTrue,
      );
    });

    test('matches RenderObject slice names', () {
      expect(
        widgetMatchesSliceName('Paragraph', 'RenderParagraph'),
        isTrue,
      );
      expect(
        widgetMatchesSliceName('IndexedStack', 'RenderIndexedStack'),
        isTrue,
      );
    });

    test('rejects unrelated names', () {
      expect(
        widgetMatchesSliceName('RightToolsPanel', 'Scavenge'),
        isFalse,
      );
      expect(
        widgetMatchesSliceName('Foo', 'Bar'),
        isFalse,
      );
    });
  });

  group('normalizeWidgetName', () {
    test('strips generic parameters', () {
      expect(
        normalizeWidgetName('BlocProvider<FileTreeCubit>'),
        'BlocProvider',
      );
    });
  });

  group('widgetMatchesDartMethodSlice', () {
    test('links Text widgets to RenderParagraph methods', () {
      expect(
        widgetMatchesDartMethodSlice('Text', 'RenderParagraph.getDryLayout'),
        isTrue,
      );
      expect(
        widgetMatchesDartMethodSlice(
          'RichText',
          'RenderParagraph.paint',
        ),
        isTrue,
      );
    });

    test('matches render class names directly', () {
      expect(
        widgetMatchesDartMethodSlice(
          'IndexedStack',
          'RenderIndexedStack.performLayout',
        ),
        isTrue,
      );
    });

    test('rejects unrelated pairs', () {
      expect(
        widgetMatchesDartMethodSlice('RightToolsPanel', 'Scavenge'),
        isFalse,
      );
    });
  });
}
