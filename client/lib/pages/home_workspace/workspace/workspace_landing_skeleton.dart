import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Lightweight center-pane placeholder while [WorkspaceChatLanding] mounts.
///
/// Header bar stubs + compose card outline — no watches, no TextField.
class WorkspaceLandingSkeleton extends StatelessWidget {
  const WorkspaceLandingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final bar = cs.onSurface.withValues(alpha: 0.08);
    final outline = cs.outlineVariant.withValues(alpha: 0.5);

    return ColoredBox(
      color: cs.surface,
      child: SizedBox.expand(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.xl,
              vertical: spacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _Bar(width: 120, height: 28, color: bar),
                      SizedBox(width: spacing.sm),
                      _Bar(width: 100, height: 28, color: bar),
                    ],
                  ),
                  SizedBox(height: spacing.sm),
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: outline),
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                    ),
                    padding: EdgeInsets.all(spacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _Bar(width: 180, height: 14, color: bar),
                        ),
                        SizedBox(height: spacing.md),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: bar,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            _Bar(width: 64, height: 24, color: bar),
                            SizedBox(width: spacing.sm),
                            _Bar(width: 64, height: 24, color: bar),
                            const Spacer(),
                            _Bar(width: 72, height: 32, color: bar),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
