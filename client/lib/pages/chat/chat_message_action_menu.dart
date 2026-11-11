import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/app_toast/app_toast.dart';

/// Injected so tests can assert the copied text without mocking the platform
/// channel (matches AGENTS.md "mock at the boundary via injection").
typedef ChatMessageClipboardWriter = Future<void> Function(String text);

Future<void> _defaultClipboardWriter(String text) =>
    Clipboard.setData(ClipboardData(text: text));

/// Callbacks for the message-level actions that the host already wires into
/// [AiMessageView]. Null hides the item.
@immutable
class ChatMessageActionHandlers {
  const ChatMessageActionHandlers({
    this.onRetry,
    this.onEdit,
    this.onFork,
    this.onPreviousVersion,
    this.onNextVersion,
  });

  final VoidCallback? onRetry;
  final VoidCallback? onEdit;
  final VoidCallback? onFork;
  final VoidCallback? onPreviousVersion;
  final VoidCallback? onNextVersion;
}

/// Pure menu-item builder. Order mirrors [AiMessageActionBar]; the rewind
/// group is bracketed by dividers so a plain message stays a 2-item menu.
List<TpActionMenuSpec> buildChatMessageActionSpecs(
  BuildContext context, {
  required AiMessage message,
  required bool deliveryFailed,
  required bool showsVersion,
  required bool rewindEnabled,
  required ChatMessageActionHandlers handlers,
  required ChatMessageClipboardWriter writeClipboard,
  required ValueChanged<String> onFeedback,
}) {
  final l10n = context.l10n;
  final plain = plainTextForCopy(message);
  final markdown = markdownForExport(message);

  void copy(String text) {
    unawaited(writeClipboard(text));
    onFeedback(l10n.ai.messageCopied);
  }

  final rewindItems = <TpActionMenuSpec>[
    if (handlers.onEdit != null)
      TpActionMenuSpec.item(
        icon: Icons.edit_outlined,
        label: l10n.edit.userMessage,
        enabled: rewindEnabled,
        onAction: handlers.onEdit,
      ),
    if (handlers.onFork != null)
      TpActionMenuSpec.item(
        icon: Icons.call_split,
        label: l10n.forkFromHere,
        enabled: rewindEnabled,
        onAction: handlers.onFork,
      ),
    if (showsVersion && handlers.onPreviousVersion != null)
      TpActionMenuSpec.item(
        icon: Icons.chevron_left,
        label: l10n.branchPrevious,
        enabled: rewindEnabled,
        onAction: handlers.onPreviousVersion,
      ),
    if (showsVersion && handlers.onNextVersion != null)
      TpActionMenuSpec.item(
        icon: Icons.chevron_right,
        label: l10n.branchNext,
        enabled: rewindEnabled,
        onAction: handlers.onNextVersion,
      ),
  ];

  return <TpActionMenuSpec>[
    if (deliveryFailed && handlers.onRetry != null)
      TpActionMenuSpec.item(
        icon: Icons.refresh_rounded,
        label: l10n.session.historyRetry,
        onAction: handlers.onRetry,
      ),
    TpActionMenuSpec.item(
      icon: Icons.copy_rounded,
      label: l10n.copy,
      enabled: plain.isNotEmpty,
      onAction: () => copy(plain),
    ),
    if (rewindItems.isNotEmpty) const TpActionMenuSpec.divider(),
    ...rewindItems,
    if (rewindItems.isNotEmpty) const TpActionMenuSpec.divider(),
    TpActionMenuSpec.item(
      icon: Icons.description_outlined,
      label: l10n.ai.messageExportMarkdown,
      enabled: markdown.isNotEmpty,
      onAction: () => copy(markdown),
    ),
  ];
}

Future<void> showChatMessageActionMenu(
  BuildContext context, {
  required Offset globalPosition,
  required AiMessage message,
  required bool deliveryFailed,
  required bool showsVersion,
  required bool rewindEnabled,
  required ChatMessageActionHandlers handlers,
  ChatMessageClipboardWriter writeClipboard = _defaultClipboardWriter,
  ValueChanged<String>? onFeedback,
}) {
  final feedback =
      onFeedback ??
      (String text) => AppToast.show(
        context,
        message: text,
        variant: TpToastVariant.success,
      );
  return showTpActionMenuFromSpecs<void>(
    context: context,
    globalPosition: globalPosition,
    specs: buildChatMessageActionSpecs(
      context,
      message: message,
      deliveryFailed: deliveryFailed,
      showsVersion: showsVersion,
      rewindEnabled: rewindEnabled,
      handlers: handlers,
      writeClipboard: writeClipboard,
      onFeedback: feedback,
    ),
  );
}
