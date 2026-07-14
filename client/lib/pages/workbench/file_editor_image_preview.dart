import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';

import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';

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

  late final PhotoViewController _controller;
  late final PhotoViewScaleStateController _scaleStateController;
  StreamSubscription<PhotoViewControllerValue>? _scaleSub;
  double? _scale;
  double? _baselineScale;
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
    if (next == null || next == _scale) return;
    _baselineScale ??= next;
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
    _scaleStateController.scaleState = factor > 1
        ? PhotoViewScaleState.zoomedIn
        : PhotoViewScaleState.zoomedOut;
    _controller.scale = current * factor;
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
      ({bool loading, String? error, Uint8List? bytes})
    >((c) {
      final bucket = c.state.bucket(widget.workspaceId);
      return (
        loading: bucket.loadingPaths.contains(widget.path),
        error: bucket.errorByPath[widget.path],
        bytes: c.bytesFor(widget.workspaceId, widget.path),
      );
    });
    final cs = Theme.of(context).colorScheme;
    final canZoom = model.bytes != null && model.error == null;

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
                    style: AppTextStyles.of(context).mdSemibold,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.shortcutsZoomOut,
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed: canZoom ? () => _zoomBy(1 / _zoomStep) : null,
                ),
                Text('$_scalePercent%', style: AppTextStyles.of(context).sm),
                IconButton(
                  tooltip: context.l10n.shortcutsZoomIn,
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: canZoom ? () => _zoomBy(_zoomStep) : null,
                ),
                IconButton(
                  tooltip: context.l10n.shortcutsZoomReset,
                  icon: const Icon(Icons.fit_screen_outlined, size: 18),
                  onPressed: canZoom
                      ? () => _scaleStateController.scaleState =
                            PhotoViewScaleState.initial
                      : null,
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
    ({bool loading, String? error, Uint8List? bytes}) model,
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
    final bytes = model.bytes;
    if (bytes == null) {
      return Center(child: Text(l10n.editorNotReady));
    }
    return PhotoView(
      imageProvider: MemoryImage(bytes),
      controller: _controller,
      scaleStateController: _scaleStateController,
      minScale: PhotoViewComputedScale.contained * 0.5,
      maxScale: PhotoViewComputedScale.contained * 4,
      initialScale: PhotoViewComputedScale.contained,
      backgroundDecoration: BoxDecoration(color: cs.workspaceCard),
      scaleStateCycle: (_) => PhotoViewScaleState.initial,
      errorBuilder: (context, error, stackTrace) {
        _reportDecodeFailed();
        return const SizedBox.shrink();
      },
    );
  }
}
