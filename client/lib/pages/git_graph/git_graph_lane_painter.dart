import 'package:flutter/material.dart';

import '../../models/git_graph.dart';

/// rounded 风格 lane 绘制策略。后续 angular 实现同一签名即可替换。
class GitGraphLanePainter extends CustomPainter {
  GitGraphLanePainter({
    required this.edges,
    this.node,
    required this.palette,
    this.laneWidth = defaultLaneWidth,
  });

  static const double defaultLaneWidth = 14;
  static const double nodeRadius = 4.5;

  final List<GitGraphEdge> edges;
  final GitGraphNode? node;
  final List<Color> palette;
  final double laneWidth;

  Color _colorOf(int index) => palette[index % palette.length];

  double _x(int lane) => laneWidth / 2 + lane * laneWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    for (final edge in edges) {
      final paint = Paint()
        ..color = _colorOf(edge.colorIndex)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final x0 = _x(edge.fromLane);
      final x1 = _x(edge.toLane);
      if (edge.isStraight) {
        canvas.drawLine(Offset(x0, 0), Offset(x1, h), paint);
      } else {
        final path = Path()
          ..moveTo(x0, 0)
          ..cubicTo(x0, h / 2, x1, h / 2, x1, h);
        canvas.drawPath(path, paint);
      }
    }
    final n = node;
    if (n != null) {
      final color = _colorOf(n.colorIndex);
      final center = Offset(_x(n.lane), h / 2);
      final fill = Paint()..color = color;
      canvas.drawCircle(center, nodeRadius, fill);
      final ring = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, nodeRadius + 1.5, ring);
    }
  }

  @override
  bool shouldRepaint(covariant GitGraphLanePainter old) {
    if (old.node != node) return true;
    if (old.edges.length != edges.length) return true;
    for (var i = 0; i < edges.length; i++) {
      if (old.edges[i] != edges[i]) return true;
    }
    return false;
  }
}
