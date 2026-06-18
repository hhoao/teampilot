import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/workspace.dart';
import '../models/workspace_icon_ref.dart';
import '../services/workspace/workspace_icon_service.dart';
import '../services/workspace/workspace_icon_storage.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/workspace_layout.dart';
import '../utils/workspace_geometry_catalog.dart';
import '../utils/workspace_icon_resolver.dart';

/// Renders a workspace avatar from [Workspace.icon].
class WorkspaceIcon extends StatelessWidget {
  const WorkspaceIcon({
    required this.workspace,
    this.previewIcon,
    this.size = 64,
    this.borderRadius = 17,
    this.padding = 10,
    super.key,
  });

  factory WorkspaceIcon.fromWorkspace(
    Workspace workspace, {
    WorkspaceIconRef? previewIcon,
    double size = 64,
    double borderRadius = 17,
    double padding = 10,
    Key? key,
  }) {
    return WorkspaceIcon(
      key: key,
      workspace: workspace,
      previewIcon: previewIcon,
      size: size,
      borderRadius: borderRadius,
      padding: padding,
    );
  }

  final Workspace workspace;
  final WorkspaceIconRef? previewIcon;
  final double size;
  final double borderRadius;
  final double padding;

  Workspace get _displayWorkspace =>
      previewIcon == null ? workspace : workspace.copyWith(icon: previewIcon);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolved = resolveWorkspaceIcon(_displayWorkspace);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(padding),
      child: switch (resolved) {
        ResolvedWorkspaceGeometryIcon(:final assetPath) => SvgPicture.asset(
          assetPath,
          fit: BoxFit.contain,
          semanticsLabel: assetPath,
        ),
        ResolvedWorkspaceCustomIcon(:final relativePath) =>
          _CustomWorkspaceIconImage(
            workspace: workspace,
            relativePath: relativePath,
          ),
      },
    );
  }
}

class _CustomWorkspaceIconImage extends StatefulWidget {
  const _CustomWorkspaceIconImage({
    required this.workspace,
    required this.relativePath,
  });

  final Workspace workspace;
  final String relativePath;

  @override
  State<_CustomWorkspaceIconImage> createState() =>
      _CustomWorkspaceIconImageState();
}

class _CustomWorkspaceIconImageState extends State<_CustomWorkspaceIconImage> {
  late Future<List<int>?> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes();
  }

  @override
  void didUpdateWidget(covariant _CustomWorkspaceIconImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath) {
      _bytesFuture = _loadBytes();
    }
  }

  Future<List<int>?> _loadBytes() {
    return workspaceIconService.loadCustomBytes(
      workspaceDir: WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath)
          .workspaceDir(widget.workspace.workspaceId),
      relativePath: widget.relativePath,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>?>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _geometryFallback();
        }
        final data = Uint8List.fromList(bytes);
        if (WorkspaceIconStorage.isSvgPath(widget.relativePath)) {
          return SvgPicture.memory(
            data,
            fit: BoxFit.contain,
            semanticsLabel: widget.relativePath,
          );
        }
        return Image.memory(
          data,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _geometryFallback(),
        );
      },
    );
  }

  Widget _geometryFallback() {
    final asset = workspaceGeometryAssetForWorkspaceId(widget.workspace.workspaceId);
    return SvgPicture.asset(
      asset,
      fit: BoxFit.contain,
      semanticsLabel: asset,
    );
  }
}
