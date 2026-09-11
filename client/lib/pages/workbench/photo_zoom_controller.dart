import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

/// Shared PhotoView zoom plumbing for the workbench file-preview panes
/// (bitmap [FileEditorImagePreview], SVG SvgPreviewPane).
///
/// Contract: fit-to-pane initial scale; initial/reset upscale clamped to
/// 1:1 (one image unit per logical pixel); 0.25–8.0 zoom range; wheel zoom;
/// `scalePercent` relative to the contained baseline.
mixin PhotoZoomControllerMixin<T extends StatefulWidget> on State<T> {
  static const zoomStep = 1.25;

  /// Absolute PhotoView scale: 1.0 = one image pixel per logical pixel.
  static const nativeScale = 1.0;
  static const minScale = 0.25;
  static const maxScale = 8.0;

  final PhotoViewController controller = PhotoViewController();
  final PhotoViewScaleStateController scaleStateController =
      PhotoViewScaleStateController();

  StreamSubscription<PhotoViewControllerValue>? _scaleSub;
  double? _scale;
  double? _baselineScale;
  bool _cappedInitialUpscale = false;

  @override
  void initState() {
    super.initState();
    _scaleSub = controller.outputStateStream.listen(_onControllerValue);
  }

  void _onControllerValue(PhotoViewControllerValue value) {
    final next = value.scale;
    if (next == null) return;
    // Fit to the pane but never upscale past 1:1 on open.
    if (!_cappedInitialUpscale && next > nativeScale) {
      _cappedInitialUpscale = true;
      controller.scale = nativeScale;
      return;
    }
    _cappedInitialUpscale = true;
    if (next == _scale) return;
    _baselineScale ??= next <= nativeScale ? next : nativeScale;
    if (!mounted) return;
    setState(() => _scale = next);
  }

  int get scalePercent {
    final current = _scale;
    final base = _baselineScale;
    if (current == null || base == null || base == 0) return 100;
    return ((current / base) * 100).round();
  }

  void zoomBy(double factor) {
    final current = controller.scale;
    if (current == null) return;
    controller.scale = (current * factor).clamp(minScale, maxScale);
  }

  /// Fit in the pane, but never larger than native 1:1.
  void resetZoom() {
    scaleStateController.scaleState = PhotoViewScaleState.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scale = controller.scale;
      if (scale != null && scale > nativeScale) {
        controller.scale = nativeScale;
      }
    });
  }

  /// Discards the fit baseline and clamp bookkeeping so the next controller
  /// event re-derives them (e.g. the host pane retargeted to a new file and
  /// the old baseline no longer applies).
  void resetZoomBaseline() {
    controller.reset();
    scaleStateController.reset();
    _baselineScale = null;
    _scale = null;
    _cappedInitialUpscale = false;
  }

  void onZoomPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    zoomBy(event.scrollDelta.dy < 0 ? zoomStep : 1 / zoomStep);
  }

  /// `scaleStateCycle` for panes that clamp upscale to 1:1.
  PhotoViewScaleState clampCycle(void _) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scale = controller.scale;
      if (scale != null && scale > nativeScale) {
        controller.scale = nativeScale;
      }
    });
    return PhotoViewScaleState.initial;
  }

  @override
  void dispose() {
    _scaleSub?.cancel();
    controller.dispose();
    scaleStateController.dispose();
    super.dispose();
  }
}
