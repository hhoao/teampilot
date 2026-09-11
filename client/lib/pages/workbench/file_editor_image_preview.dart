import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';

import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import 'photo_zoom_controller.dart';

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

class _FileEditorImagePreviewState extends State<FileEditorImagePreview>
    with PhotoZoomControllerMixin<FileEditorImagePreview> {
  bool _decodeFailureReported = false;

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
                  onPressed: canZoom
                      ? () => zoomBy(1 / PhotoZoomControllerMixin.zoomStep)
                      : null,
                ),
                Text('$scalePercent%', style: TpTextStyles.of(context).sm),
                IconButton(
                  tooltip: context.l10n.shortcutsZoomIn,
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: canZoom
                      ? () => zoomBy(PhotoZoomControllerMixin.zoomStep)
                      : null,
                ),
                IconButton(
                  tooltip: context.l10n.shortcutsZoomReset,
                  icon: const Icon(Icons.fit_screen_outlined, size: 18),
                  onPressed: canZoom ? resetZoom : null,
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
        onPointerSignal: onZoomPointerSignal,
        child: PhotoView(
          imageProvider: MemoryImage(bytes),
          controller: controller,
          scaleStateController: scaleStateController,
          // medium: Image resamples (not Transform) — avoids soft HiDPI blur.
          filterQuality: FilterQuality.medium,
          minScale: PhotoZoomControllerMixin.minScale,
          maxScale: PhotoZoomControllerMixin.maxScale,
          // Contained for large images; open/reset clamp upscale to 1:1.
          initialScale: PhotoViewComputedScale.contained,
          // Match [FileEditorSurface] shell / floating window chrome.
          backgroundDecoration: BoxDecoration(color: cs.surface),
          scaleStateCycle: clampCycle,
          errorBuilder: (context, error, stackTrace) {
            _reportDecodeFailed();
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
