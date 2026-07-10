/// Live per-display UI zoom baseline (`1 / devicePixelRatio`) for shortcut
/// zoom steps. Updated from [MaterialApp]'s builder once [MediaQuery] is
/// available; defaults to `1.0` until the first frame.
class UiZoomBaseline {
  double value = 1.0;
}
