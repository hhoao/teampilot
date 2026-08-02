import 'dart:async';
import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';

import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';

/// Workbench file-tab surface for bitmap image preview (zoom via photo_view).
class FileEditorImagePreview extends StatefulWidget {
  const FileEditorImagePreview({
    required this.workspaceId,
    required this.path,
    super.key,
  });

  final String workspaceId;
  final String path;

  @override
  State<FileEditorImagePreview> createState() => _FileEditorImagePreviewState();
}

class _FileEditorImagePreviewState extends State<FileEditorImagePreview> {
  static const _zoomStep = 1.25;
  /// Absolute PhotoView scale: 1.0 = one image pixel per logical pixel.
  static const _nativeScale = 1.0;
  static const _minScale = 0.25;
  static const _maxScale = 8.0;

  late final PhotoViewController _controller;
  late final PhotoViewScaleStateController _scaleStateController;
  StreamSubscription<PhotoViewControllerValue>? _scaleSub;
  double? _scale;
  double? _baselineScale;
  bool _cappedInitialUpscale = false;
  bool _decodeFailureReported = false;

  @override
  void initState() {
    super.initState();
    _controller = PhotoViewController();
    _scaleStateController = PhotoViewScaleStateController();
    _scaleSub = _controller.outputStateStream.listen(_onControllerValue);
  }

  void _onControllerValue(PhotoViewControllerValue value) {
    final next = value.scale;
    if (next == null) return;
    // Match Orca: fit to the pane but never upscale past 1:1 on open.
    if (!_cappedInitialUpscale && next > _nativeScale) {
      _cappedInitialUpscale = true;
      _controller.scale = _nativeScale;
      return;
    }
    _cappedInitialUpscale = true;
    if (next == _scale) return;
    _baselineScale ??= next <= _nativeScale ? next : _nativeScale;
    if (!mounted) return;
    setState(() => _scale = next);
  }

  @override
  void dispose() {
    _scaleSub?.cancel();
    _controller.dispose();
    _scaleStateController.dispose();
    super.dispose();
  }

  int get _scalePercent {
    final current = _scale;
    final base = _baselineScale;
    if (current == null || base == null || base == 0) return 100;
    return ((current / base) * 100).round();
  }

  void _zoomBy(double factor) {
    final current = _controller.scale;
    if (current == null) return;
    _controller.scale = (current * factor).clamp(_minScale, _maxScale);
  }

  /// Fit in the pane, but never larger than native 1:1 (same as Orca).
  void _resetZoom() {
    _scaleStateController.scaleState = PhotoViewScaleState.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scale = _controller.scale;
      if (scale != null && scale > _nativeScale) {
        _controller.scale = _nativeScale;
      }
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    _zoomBy(event.scrollDelta.dy < 0 ? _zoomStep : 1 / _zoomStep);
  }

  void _reportDecodeFailed() {
    if (_decodeFailureReported) return;
    _decodeFailureReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<EditorCubit>().reportImageDecodeFailed(
        widget.workspaceId,
        widget.path,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = context.select<
      EditorCubit,
      ({bool loading, String? error, bool hasBytes})
    >((c) {
      final bucket = c.state.bucket(widget.workspaceId);
      return (
        loading: bucket.loadingPaths.contains(widget.path),
        error: bucket.errorByPath[widget.path],
        hasBytes: c.bytesFor(widget.workspaceId, widget.path) != null,
      );
    });
    final cs = Theme.of(context).colorScheme;
    final canZoom = model.hasBytes && model.error == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.basename(widget.path),
                    style: TpTextStyles.of(context).mdSemibold,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.shortcutsZoomOut,
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed: canZoom ? () => _zoomBy(1 / _zoomStep) : null,
                ),
                Text('$_scalePercent%', style: TpTextStyles.of(context).sm),
                IconButton(
                  tooltip: context.l10n.shortcutsZoomIn,
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: canZoom ? () => _zoomBy(_zoomStep) : null,
                ),
                IconButton(
                  tooltip: context.l10n.shortcutsZoomReset,
                  icon: const Icon(Icons.fit_screen_outlined, size: 18),
                  onPressed: canZoom ? _resetZoom : null,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody(context, model, cs)),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    ({bool loading, String? error, bool hasBytes}) model,
    ColorScheme cs,
  ) {
    final l10n = context.l10n;
    if (model.loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (model.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.editorPanelErrorMessage(model.error!),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!model.hasBytes) {
      return Center(child: Text(l10n.editorNotReady));
    }
    final bytes = context.read<EditorCubit>().bytesFor(
      widget.workspaceId,
      widget.path,
    );
    if (bytes == null) {
      return Center(child: Text(l10n.editorNotReady));
    }
    return ClipRect(
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: PhotoView(
          imageProvider: MemoryImage(bytes),
          controller: _controller,
          scaleStateController: _scaleStateController,
          // medium: Image resamples (not Transform) — avoids soft HiDPI blur.
          filterQuality: FilterQuality.medium,
          minScale: _minScale,
          maxScale: _maxScale,
          // Contained for large images; open/reset clamp upscale to 1:1.
          initialScale: PhotoViewComputedScale.contained,
          // Match [FileEditorSurface] shell / floating window chrome.
          backgroundDecoration: BoxDecoration(color: cs.surface),
          scaleStateCycle: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final scale = _controller.scale;
              if (scale != null && scale > _nativeScale) {
                _controller.scale = _nativeScale;
              }
            });
            return PhotoViewScaleState.initial;
          },
          errorBuilder: (context, error, stackTrace) {
            _reportDecodeFailed();
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
