import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/app_project.dart';
import '../models/project_icon_ref.dart';
import '../services/project/project_icon_service.dart';
import '../services/project/project_icon_storage.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/workspace_layout.dart';
import '../utils/project_geometry_catalog.dart';
import '../utils/project_icon_resolver.dart';

/// Renders a project avatar from [AppProject.icon].
class ProjectIcon extends StatelessWidget {
  const ProjectIcon({
    required this.project,
    this.previewIcon,
    this.size = 64,
    this.borderRadius = 17,
    this.padding = 10,
    super.key,
  });

  factory ProjectIcon.fromProject(
    AppProject project, {
    ProjectIconRef? previewIcon,
    double size = 64,
    double borderRadius = 17,
    double padding = 10,
    Key? key,
  }) {
    return ProjectIcon(
      key: key,
      project: project,
      previewIcon: previewIcon,
      size: size,
      borderRadius: borderRadius,
      padding: padding,
    );
  }

  final AppProject project;
  final ProjectIconRef? previewIcon;
  final double size;
  final double borderRadius;
  final double padding;

  AppProject get _displayProject =>
      previewIcon == null ? project : project.copyWith(icon: previewIcon);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolved = resolveProjectIcon(_displayProject);

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
        ResolvedProjectGeometryIcon(:final assetPath) => SvgPicture.asset(
          assetPath,
          fit: BoxFit.contain,
          semanticsLabel: assetPath,
        ),
        ResolvedProjectCustomIcon(:final relativePath) =>
          _CustomProjectIconImage(
            project: project,
            relativePath: relativePath,
          ),
      },
    );
  }
}

class _CustomProjectIconImage extends StatefulWidget {
  const _CustomProjectIconImage({
    required this.project,
    required this.relativePath,
  });

  final AppProject project;
  final String relativePath;

  @override
  State<_CustomProjectIconImage> createState() =>
      _CustomProjectIconImageState();
}

class _CustomProjectIconImageState extends State<_CustomProjectIconImage> {
  late Future<List<int>?> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes();
  }

  @override
  void didUpdateWidget(covariant _CustomProjectIconImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath) {
      _bytesFuture = _loadBytes();
    }
  }

  Future<List<int>?> _loadBytes() {
    return projectIconService.loadCustomBytes(
      projectDir: WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath)
          .projectDir(widget.project.projectId),
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
        if (ProjectIconStorage.isSvgPath(widget.relativePath)) {
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
    final asset = projectGeometryAssetForProjectId(widget.project.projectId);
    return SvgPicture.asset(
      asset,
      fit: BoxFit.contain,
      semanticsLabel: asset,
    );
  }
}
