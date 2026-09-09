import 'dart:async';
import 'dart:typed_data';

import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:photo_view/photo_view.dart';

import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/editor/editor_messages.dart';
import '../../services/io/filesystem.dart';
import 'photo_zoom_controller.dart';

/// Workbench SVG preview: renders on-disk bytes with zoom (PhotoView) and a
/// zoom toolbar. Unsaved editor edits are not reflected — the pane re-reads
/// when the file transitions dirty -> saved. The SVG natural size (declared
/// width/height, else viewBox) defines 1:1; parse failure degrades to
/// fit-without-natural-size and surfaces via the decode-failure channel.
class SvgPreviewPane extends StatefulWidget {
  const SvgPreviewPane({
    required this.workspaceId,
    required this.path,
    this.fs,
    super.key,
  });

  final String workspaceId;
  final String path;
  final Filesystem? fs;

  @override
  State<SvgPreviewPane> createState() => _SvgPreviewPaneState();
}

class _SvgPreviewPaneState extends State<SvgPreviewPane>
    with PhotoZoomControllerMixin<SvgPreviewPane> {
  Filesystem? _fs;
  bool _loadStarted = false;
  bool _loading = true;
  Uint8List? _bytes;
  Size? _naturalSize;
  bool _readFailed = false;
  int? _decodeFailureReportedSeq;
  int _loadSeq = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fs ??=
        widget.fs ??
        context.read<EditorCubit>().fsFor(widget.workspaceId, widget.path);
    if (!_loadStarted) {
      _loadStarted = true;
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(SvgPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.workspaceId != widget.workspaceId) {
      // Retarget: re-resolve fs and reload. Stale in-flight loads are
      // discarded via the sequence token, and the zoom baseline must not
      // stay anchored to the previous file's fit.
      _fs =
          widget.fs ??
          context.read<EditorCubit>().fsFor(widget.workspaceId, widget.path);
      _loadStarted = true;
      _decodeFailureReportedSeq = null;
      resetZoomBaseline();
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _readFailed = false;
    });
    final fs = _fs;
    if (fs == null) return;
    List<int>? raw;
    try {
      raw = await fs.readBytes(widget.path);
    } on Object {
      raw = null;
    }
    if (!mounted || seq != _loadSeq) return;
    if (raw == null) {
      setState(() {
        _loading = false;
        _readFailed = true;
        _bytes = null;
        _naturalSize = null;
      });
      return;
    }
    final bytes = Uint8List.fromList(raw);
    // Natural size only; SvgPicture.memory re-parses for rendering, so
    // dispose the probe picture immediately.
    Size? natural;
    try {
      final info = await vg.loadPicture(SvgBytesLoader(bytes), null);
      try {
        natural = info.size;
      } finally {
        info.picture.dispose();
      }
    } on Object {
      natural = null;
    }
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _loading = false;
      _bytes = bytes;
      _naturalSize =
          (natural != null && natural.width > 0 && natural.height > 0)
          ? natural
          : null;
    });
  }

  void _reportDecodeFailed({
    required String workspaceId,
    required String path,
    required int seq,
  }) {
    if (_decodeFailureReportedSeq == seq) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || seq != _loadSeq) return;
      if (_decodeFailureReportedSeq == seq) return;
      _decodeFailureReportedSeq = seq;
      context.read<EditorCubit>().reportImageDecodeFailed(workspaceId, path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final hasBytes = _bytes != null && !_readFailed;
    final canZoom = hasBytes && !_loading;

    return BlocListener<EditorCubit, EditorState>(
      // Unsaved edits must not affect the preview; re-read once saved.
      listenWhen: (previous, next) =>
          previous.bucket(widget.workspaceId).isDirty(widget.path) &&
          !next.bucket(widget.workspaceId).isDirty(widget.path),
      listener: (context, state) {
        _decodeFailureReportedSeq = null;
        unawaited(_load());
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: l10n.shortcutsZoomOut,
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: canZoom
                        ? () => zoomBy(1 / PhotoZoomControllerMixin.zoomStep)
                        : null,
                  ),
                  Text('$scalePercent%', style: TpTextStyles.of(context).sm),
                  IconButton(
                    tooltip: l10n.shortcutsZoomIn,
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: canZoom
                        ? () => zoomBy(PhotoZoomControllerMixin.zoomStep)
                        : null,
                  ),
                  IconButton(
                    tooltip: l10n.shortcutsZoomReset,
                    icon: const Icon(Icons.fit_screen_outlined, size: 18),
                    onPressed: canZoom ? resetZoom : null,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(context, l10n, cs)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_readFailed || _bytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.editorPanelErrorMessage(EditorMessage.couldNotRead),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final workspaceId = widget.workspaceId;
    final path = widget.path;
    final seq = _loadSeq;
    return ClipRect(
      child: Listener(
        onPointerSignal: onZoomPointerSignal,
        child: PhotoView.customChild(
          childSize: _naturalSize,
          controller: controller,
          scaleStateController: scaleStateController,
          minScale: PhotoZoomControllerMixin.minScale,
          maxScale: PhotoZoomControllerMixin.maxScale,
          initialScale: PhotoViewComputedScale.contained,
          backgroundDecoration: BoxDecoration(color: cs.surface),
          scaleStateCycle: clampCycle,
          child: SvgPicture.memory(
            _bytes!,
            errorBuilder: (context, error, stackTrace) {
              _reportDecodeFailed(
                workspaceId: workspaceId,
                path: path,
                seq: seq,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
