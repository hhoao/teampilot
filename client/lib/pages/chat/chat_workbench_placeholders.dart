import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/debounce/debounce.dart';

class ChatWorkbenchSessionLoadingView extends StatelessWidget {
  const ChatWorkbenchSessionLoadingView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: AppTextStyles.of(
              context,
            ).body.copyWith(color: textBase.withValues(alpha: 0.68)),
          ),
        ],
      ),
    );
  }
}

class ChatWorkbenchTerminalPlaceholder extends StatelessWidget {
  const ChatWorkbenchTerminalPlaceholder({super.key, 
    required this.onConnect,
    this.connectDisabled = false,
    this.memberName,
    this.launchError,
  });

  final VoidCallback onConnect;
  final bool connectDisabled;
  final String? memberName;
  final String? launchError;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final member = memberName?.trim();
    final error = launchError?.trim();
    final hasError = error != null && error.isNotEmpty;
    final subtitle = member != null && member.isNotEmpty
        ? l10n.sessionReadySubtitle(member)
        : l10n.sessionReadySubtitleGeneric;

    return Align(
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    cs.primary.withValues(alpha: 0.12),
                    cs.surfaceContainerHighest,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Icon(
                    Icons.forum_outlined,
                    size: context.appIconSizes.md,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                hasError ? l10n.sessionFailedTitle : l10n.sessionReadyTitle,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: hasError ? cs.error : null,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              if (hasError) ...[
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.error.withValues(alpha: 0.35)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      error,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onErrorContainer,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.start,
                    ),
                  ),
                ),
              ],
              if (!hasError) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.sessionReadyHint,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: connectDisabled
                    ? null
                    : throttledOnPressed(
                        'chat_workbench_session_start',
                        onConnect,
                      ),
                icon: Icon(
                  hasError ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                  size: context.appIconSizes.md,
                ),
                label: Text(
                  hasError ? l10n.sessionRetryButton : l10n.sessionStartButton,
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  minimumSize: const Size(0, 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
