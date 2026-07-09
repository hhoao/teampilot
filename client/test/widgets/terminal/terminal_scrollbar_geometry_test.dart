import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/terminal/terminal_scrollbar_geometry.dart';

void main() {
  group('TerminalScrollbarGeometry', () {
    const history = 1000;
    const viewport = 24;
    const track = 400.0;

    TerminalScrollbarGeometry geom({
      double scrollOffset = 0,
    }) =>
        TerminalScrollbarGeometry(
          historySize: history,
          viewportRows: viewport,
          scrollOffsetLines: scrollOffset,
          trackHeight: track,
        );

    test('live bottom: thumb at track bottom', () {
      final g = geom();
      expect(g.positionFraction, 1.0);
      expect(g.thumbTop, closeTo(track - g.thumbHeight, 0.01));
    });

    test('history top: thumb at track top', () {
      final g = geom(scrollOffset: history.toDouble());
      expect(g.positionFraction, 0.0);
      expect(g.thumbTop, 0.0);
    });

    test('pointer at track bottom maps to live bottom', () {
      final g = geom();
      final fraction = TerminalScrollbarGeometry.positionFractionFromTrackDy(
        localDy: track,
        trackHeight: track,
        thumbHeight: g.thumbHeight,
      );
      expect(fraction, closeTo(1.0, 0.01));
      expect(g.scrollOffsetForPosition(fraction), closeTo(0.0, 1.0));
    });

    test('pointer at track top maps to history top', () {
      final g = geom();
      final fraction = TerminalScrollbarGeometry.positionFractionFromTrackDy(
        localDy: 0,
        trackHeight: track,
        thumbHeight: g.thumbHeight,
      );
      expect(fraction, closeTo(0.0, 0.01));
      expect(
        g.scrollOffsetForPosition(fraction),
        closeTo(history.toDouble(), 1.0),
      );
    });

    test('round-trip mid-track', () {
      final g = geom();
      final midDy = track / 2;
      final fraction = TerminalScrollbarGeometry.positionFractionFromTrackDy(
        localDy: midDy,
        trackHeight: track,
        thumbHeight: g.thumbHeight,
      );
      final offset = g.scrollOffsetForPosition(fraction);
      expect(offset, closeTo(history / 2, history * 0.05));
    });
  });
}
