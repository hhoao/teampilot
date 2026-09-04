import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../models/config_bundle.dart';
import '../../services/cli/registry/capabilities/native_command_capability.dart';
import '../../services/commands/command_bus.dart';
import '../../services/commands/shortcut_focus.dart';
import '../../services/storage/app_storage.dart';
import '../../services/compose/compose_file_search.dart';
import '../../services/file_tree/workspace_file_index.dart';
import '../../services/search/workspace_search_indexes.dart';
import '../../services/compose/compose_clip.dart';
import '../../services/compose/compose_slash_catalog.dart';
import '../../services/compose/compose_trigger_caret.dart';
import '../../services/compose/compose_trigger_insert.dart';
import '../../services/compose/compose_trigger_query.dart';
import '../../services/cli/registry/capabilities/skill_capability.dart';
import '../../services/keyboard/compose_keyboard_shortcut_handler.dart';
import '../../services/inline_token/inline_token_palette.dart';
import 'package:shared_ui/shared_ui.dart';

/// Paste key pressed in the compose field. Re-routes Ctrl/Cmd+V out of
/// EditableText's default [PasteTextIntent] so a clipboard image can be
/// imported *without* the clipboard's text side (e.g. the file path GNOME
/// writes alongside copied image files) also being pasted as bare text.
class ComposePasteImageIntent extends Intent {
  const ComposePasteImageIntent();
}

sealed class ComposeTriggerSuggestion {}

final class ComposeTriggerFileSuggestion extends ComposeTriggerSuggestion {
  ComposeTriggerFileSuggestion(this.candidate);
  final ComposeFileCandidate candidate;
}

final class ComposeTriggerSlashSuggestion extends ComposeTriggerSuggestion {
  ComposeTriggerSlashSuggestion(this.candidate);
  final ComposeSlashCandidate candidate;
}

/// Multiline compose field with `@` file references and `/` skill/command picks.
class ComposeTriggerField extends StatefulWidget {
  /// Line threshold for collapsing an oversized paste into the clip. Typing
  /// adds at most one line per change, so only a large single insert (a paste)
  /// crosses this.
  static const kComposePasteCollapseLines = 25;

  const ComposeTriggerField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.enabled,
    required this.onChanged,
    required this.onSubmit,
    required this.canSubmit,
    required this.workspaceRoot,
    required this.skills,
    required this.plugins,
    required this.slashBundle,
    required this.mutedColor,
    required this.hintColor,
    this.skillSyntax,
    this.nativeCommands = const [],
    this.onPasteImage,
    this.clip,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final bool Function() canSubmit;
  final String workspaceRoot;
  final List<Skill> skills;
  final List<Plugin> plugins;
  final ConfigBundle slashBundle;
  final Color mutedColor;
  final Color hintColor;
  final SkillCapability? skillSyntax;
  final List<NativeCommand> nativeCommands;
  final Future<bool> Function()? onPasteImage;

  /// Optional paste-collapse buffer. When set and a single change pushes the
  /// line count past [kComposePasteCollapseLines], the whole draft moves into
  /// the clip and the visible controller is cleared.
  final ComposeClip? clip;

  @override
  State<ComposeTriggerField> createState() => _ComposeTriggerFieldState();
}

class _ComposeTriggerFieldState extends State<ComposeTriggerField> {
  late int _lastLineCount;
  final _fieldKey = GlobalKey();
  ComposeTriggerQuery? _trigger;
  List<ComposeTriggerSuggestion> _suggestions = const [];
  var _selectedIndex = 0;
  var _searchGeneration = 0;
  Timer? _searchDebounce;
  Timer? _focusClearTimer;
  Offset _menuAnchor = Offset.zero;
  VoidCallback? _newlineDisposer;
  VoidCallback? _submitDisposer;

  @override
  void initState() {
    super.initState();
    _lastLineCount = ComposeClip.countLines(widget.controller.text);
    widget.controller.addListener(_handleControllerChanged);
    widget.focusNode.addListener(_handleFocusChanged);
    if (widget.focusNode.hasFocus) {
      _registerComposeCommands();
    }
  }

  @override
  void didUpdateWidget(covariant ComposeTriggerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _lastLineCount = ComposeClip.countLines(widget.controller.text);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
    }
    if (widget.focusNode.hasFocus &&
        (oldWidget.controller != widget.controller ||
            oldWidget.onSubmit != widget.onSubmit ||
            oldWidget.canSubmit != widget.canSubmit)) {
      _registerComposeCommands();
    }
    if (oldWidget.workspaceRoot != widget.workspaceRoot ||
        oldWidget.skills != widget.skills ||
        oldWidget.plugins != widget.plugins ||
        oldWidget.slashBundle != widget.slashBundle ||
        oldWidget.skillSyntax != widget.skillSyntax ||
        oldWidget.nativeCommands != widget.nativeCommands) {
      _refreshSuggestions(immediate: true);
    }
  }

  @override
  void dispose() {
    _focusClearTimer?.cancel();
    _searchDebounce?.cancel();
    widget.controller.removeListener(_handleControllerChanged);
    widget.focusNode.removeListener(_handleFocusChanged);
    _unregisterComposeCommands();
    super.dispose();
  }

  void _registerComposeCommands() {
    _newlineDisposer?.call();
    _newlineDisposer = ComposeCommandBindings.registerNewline(
      bus: context.read<CommandBus>(),
      controller: widget.controller,
    );
    _syncSubmitRegistration();
  }

  void _unregisterComposeCommands() {
    _newlineDisposer?.call();
    _newlineDisposer = null;
    _submitDisposer?.call();
    _submitDisposer = null;
  }

  /// Keeps `compose.submit` registered only while focused and the `@` / `/`
  /// suggestion overlay is closed. While the overlay is open, Enter must
  /// only pick the highlighted suggestion (handled locally in
  /// [_handleComposeKey]) — not also fire `compose.submit` via the root
  /// dispatcher, so submit is un-registered rather than made a no-op (a
  /// registered no-op would still mark the key "handled" on the bus without
  /// telling the dispatcher/focus chain anything changed).
  void _syncSubmitRegistration() {
    _submitDisposer?.call();
    _submitDisposer = (widget.focusNode.hasFocus && !_overlayVisible)
        ? ComposeCommandBindings.registerSubmit(
            bus: context.read<CommandBus>(),
            onSubmit: widget.onSubmit,
            canSubmit: widget.canSubmit,
          )
        : null;
  }

  void _handleFocusChanged() {
    if (widget.focusNode.hasFocus) {
      _focusClearTimer?.cancel();
      _registerComposeCommands();
      return;
    }
    _unregisterComposeCommands();
    // Defer closing so overlay pointer events can select an item first.
    _focusClearTimer?.cancel();
    _focusClearTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || widget.focusNode.hasFocus) return;
      _clearSuggestions();
    });
  }

  void _handleControllerChanged() {
    _maybeCollapseOversizedPaste();
    _refreshSuggestions();
    _scheduleMenuAnchorUpdate();
  }

  /// Collapses a single oversized insert (a paste) into the clip. Typing adds
  /// at most one line per change, so only a large single insert crosses the
  /// threshold. Undo that restores the long text re-crosses it (self-heals).
  void _maybeCollapseOversizedPaste() {
    final clip = widget.clip;
    final count = ComposeClip.countLines(widget.controller.text);
    final crossed = _lastLineCount <= ComposeTriggerField.kComposePasteCollapseLines &&
        count > ComposeTriggerField.kComposePasteCollapseLines;
    // Update the running line count regardless of whether a clip is attached,
    // so an oversized paste is still detected if the clip appears later.
    _lastLineCount = count;
    if (clip == null || !crossed) return;
    clip.setPasted(widget.controller.text);
    widget.controller.clear();
    // Programmatic clear() does not fire TextField.onChanged, so ping the
    // parent's onComposeChanged (setState) so canSubmit recomputes.
    widget.onChanged(widget.controller.text);
  }

  void _scheduleMenuAnchorUpdate() {
    if (!_overlayVisible) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateMenuAnchor();
    });
  }

  void _updateMenuAnchor() {
    final fieldBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (fieldBox == null || !fieldBox.hasSize) return;

    final styles = TpTextStyles.of(context);
    final textStyle = styles.mdColored(widget.mutedColor);
    final anchor = composeTriggerMenuAnchor(
      context: context,
      fieldBox: fieldBox,
      value: widget.controller.value,
      textStyle: textStyle,
      maxWidth: fieldBox.size.width,
    );
    if (anchor == null || anchor == _menuAnchor) return;
    setState(() => _menuAnchor = anchor);
  }

  void _clearSuggestions() {
    if (_trigger == null && _suggestions.isEmpty) return;
    setState(() {
      _trigger = null;
      _suggestions = const [];
      _selectedIndex = 0;
    });
    _syncSubmitRegistration();
  }

  /// Extra chars that open the slash menu alongside `/` — e.g. `$` when the
  /// target CLI (Codex) invokes skills with `$`.
  Set<String> _skillSlashTriggers() {
    final prefix = widget.skillSyntax?.skillInvocationPrefix;
    if (prefix == null || prefix == '/') return const {};
    return {prefix};
  }

  void _refreshSuggestions({bool immediate = false}) {
    final value = widget.controller.value;
    final cursor = value.selection.isValid
        ? value.selection.baseOffset
        : value.text.length;
    final trigger = detectComposeTrigger(
      value.text,
      cursor,
      additionalSlashTriggers: _skillSlashTriggers(),
    );
    if (trigger == null) {
      _clearSuggestions();
      return;
    }

    _trigger = trigger;
    _searchDebounce?.cancel();
    if (immediate) {
      unawaited(_runSearch(trigger));
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      unawaited(_runSearch(trigger));
    });
  }

  Future<void> _runSearch(ComposeTriggerQuery trigger) async {
    final generation = ++_searchGeneration;
    late final List<ComposeTriggerSuggestion> suggestions;
    switch (trigger.kind) {
      case ComposeTriggerKind.fileReference:
        try {
          final files = await _searchComposeFiles(trigger.query);
          suggestions = [
            for (final file in files) ComposeTriggerFileSuggestion(file),
          ];
        } on Object {
          suggestions = const [];
        }
      case ComposeTriggerKind.slashInvoke:
        final slash = buildComposeSlashCandidates(
          skills: widget.skills,
          plugins: widget.plugins,
          enabledBundle: widget.slashBundle,
          query: trigger.query,
          syntax: widget.skillSyntax,
          nativeCommands: widget.nativeCommands,
        );
        suggestions = [
          for (final item in slash) ComposeTriggerSlashSuggestion(item),
        ];
    }

    if (!mounted || generation != _searchGeneration) return;
    setState(() {
      _trigger = trigger;
      _suggestions = suggestions;
      _selectedIndex = suggestions.isEmpty
          ? 0
          : _selectedIndex.clamp(0, suggestions.length - 1);
    });
    _syncSubmitRegistration();
    _scheduleMenuAnchorUpdate();
  }

  /// Resolves `@`-mention file candidates. Path-segment queries (containing
  /// `/`) list one directory directly (already cheap); plain name queries hit
  /// the shared [WorkspaceFileIndex] so the tree is walked once per root
  /// instead of on every keystroke. The compose suggestion semantics are
  /// preserved: files and directories whose name contains the query, dirs
  /// first.
  Future<List<ComposeFileCandidate>> _searchComposeFiles(String query) async {
    final segments = query
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.length > 1) {
      return searchComposeFiles(
        fs: AppStorage.fs,
        workspaceRoot: widget.workspaceRoot,
        query: query,
      );
    }
    final needle = segments.isEmpty ? '' : segments.first;
    final index = context.read<WorkspaceSearchIndexes>().fileIndexFor(
      widget.workspaceRoot,
    );
    await index.ensureFresh();
    final fileMatches = index.query(
      needle,
      mode: WorkspaceFileMatchMode.contains,
      limit: 40,
    );
    final dirs = index.queryDirectories(needle, limit: 20);
    return mergeComposeCandidates(
      fileMatches: fileMatches,
      directoryPaths: dirs,
    );
  }

  bool get _overlayVisible => _trigger != null && _suggestions.isNotEmpty;

  void _selectSuggestion(ComposeTriggerSuggestion suggestion) {
    final trigger = _trigger;
    if (trigger == null) return;

    final insertion = switch (suggestion) {
      ComposeTriggerFileSuggestion(:final candidate) => ComposeTriggerInsertion(
        text: candidate.insertText,
      ),
      ComposeTriggerSlashSuggestion(:final candidate) => candidate.insertion,
    };
    widget.controller.value = replaceComposeTrigger(
      widget.controller,
      trigger,
      insertion,
    );
    _focusClearTimer?.cancel();
    _clearSuggestions();
    widget.onChanged(widget.controller.text);
    widget.focusNode.requestFocus();
    setState(() {});
  }

  KeyEventResult _handleComposeKey(FocusNode node, KeyEvent event) {
    if (_overlayVisible && event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % _suggestions.length;
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedIndex =
              (_selectedIndex - 1 + _suggestions.length) % _suggestions.length;
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _clearSuggestions();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        _selectSuggestion(_suggestions[_selectedIndex]);
        return KeyEventResult.handled;
      }
    }

    // Enter / Mod+Enter (compose.submit / compose.newline) are matched by
    // the root ShortcutDispatcher and dispatched to the handlers registered
    // in _registerComposeCommands — nothing left to do here.
    return KeyEventResult.ignored;
  }

  /// Ctrl/Cmd+V handler from [_pasteImageShortcuts]. Tries the image import
  /// first; when an image is imported the key is fully swallowed so
  /// [EditableText]'s default paste cannot also insert the clipboard's text
  /// side (the file path a file manager writes next to copied image bytes).
  /// With no image on the clipboard, falls back to the default text paste.
  Future<Object?> _invokePasteImage(ComposePasteImageIntent intent) async {
    final onPasteImage = widget.onPasteImage;
    if (onPasteImage == null) {
      _fallbackPasteText();
      return null;
    }
    final pastedImage = await onPasteImage();
    if (pastedImage) {
      // Image imported: refresh attachments / token chips.
      widget.onChanged(widget.controller.text);
      if (mounted) setState(() {});
      return null;
    }
    _fallbackPasteText();
    return null;
  }

  void _fallbackPasteText() {
    if (!mounted) return;
    // The clipboard probe awaited; make sure focus is still inside this
    // field before re-dispatching, or the text would paste elsewhere.
    if (!widget.focusNode.hasFocus) return;
    final focusContext = widget.focusNode.context;
    if (focusContext == null) return;
    // Re-dispatch the default paste intent for the (still) focused field.
    Actions.maybeInvoke(
      focusContext,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
  }

  Map<ShortcutActivator, Intent> get _pasteImageShortcuts =>
      <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            const ComposePasteImageIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            const ComposePasteImageIntent(),
      };

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final textStyle = styles.mdColored(widget.mutedColor);

    if (_overlayVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateMenuAnchor();
      });
    }

    final lineHeight = (textStyle.fontSize ?? 14) * (textStyle.height ?? 1.35);
    final minH = lineHeight * 3;
    final maxH = lineHeight * 6;

    return ShortcutFocus(
      kind: ShortcutFocusKind.compose,
      child: Shortcuts(
        // Inner Shortcuts wins over the app-level DefaultTextEditingShortcuts:
        // the paste chord resolves to ComposePasteImageIntent first, so an
        // image import can swallow the key entirely instead of racing the
        // default PasteTextIntent (which pasted the clipboard's text side —
        // the file path next to copied image bytes — a second time).
        debugLabel: '<Compose Image Paste Shortcuts>',
        shortcuts: _pasteImageShortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            ComposePasteImageIntent: CallbackAction<ComposePasteImageIntent>(
              onInvoke: _invokePasteImage,
            ),
          },
          child: TpTextareaShell(
            minHeight: minH,
            maxHeight: maxH,
            initialHeight: minH,
            resizable: true,
            textStyle: textStyle,
            focusNode: widget.focusNode,
            builder: (context, lineCount) {
              return TpTokenTextField(
                fieldKey: _fieldKey,
                controller: widget.controller,
                focusNode: widget.focusNode,
                hint: widget.hint,
                enabled: widget.enabled,
                onChanged: widget.onChanged,
                textStyle: textStyle,
                hintStyle: styles.mdColored(widget.hintColor),
                cursorColor: widget.mutedColor,
                tokenPattern: defaultInlineTokenPattern,
                resolveTokenPalette: resolveSlashAtTokenPalette,
                // Fill the shell so blank viewport areas remain tappable.
                expands: true,
                minLines: lineCount,
                maxLines: lineCount,
                onKeyEvent: _handleComposeKey,
                overlayVisible: _overlayVisible,
                overlayAnchor: _menuAnchor,
                overlayBuilder: _overlayVisible
                    ? (context) => _ComposeTriggerSuggestionPanel(
                        suggestions: _suggestions,
                        selectedIndex: _selectedIndex,
                        onSelected: _selectSuggestion,
                        onHover: (index) =>
                            setState(() => _selectedIndex = index),
                      )
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ComposeTriggerSuggestionPanel extends StatelessWidget {
  const _ComposeTriggerSuggestionPanel({
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelected,
    required this.onHover,
  });

  final List<ComposeTriggerSuggestion> suggestions;
  final int selectedIndex;
  final ValueChanged<ComposeTriggerSuggestion> onSelected;
  final ValueChanged<int> onHover;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final styles = TpTextStyles.of(context);

    return Material(
      elevation: 8,
      shadowColor: cs.shadow.withValues(alpha: 0.18),
      color: cs.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.symmetric(vertical: spacing.xs),
          children: _buildPanelChildren(
            context: context,
            cs: cs,
            spacing: spacing,
            styles: styles,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPanelChildren({
    required BuildContext context,
    required ColorScheme cs,
    required TpSpacing spacing,
    required TpTextStyles styles,
  }) {
    final children = <Widget>[];
    ComposeSlashCandidateKind? slashSection;

    for (var index = 0; index < suggestions.length; index++) {
      final suggestion = suggestions[index];
      if (suggestion is ComposeTriggerSlashSuggestion) {
        final section = suggestion.candidate.kind;
        if (slashSection != section) {
          slashSection = section;
          children.add(
            _ComposeTriggerSectionHeader(
              label: section == ComposeSlashCandidateKind.skill
                  ? 'Skills'
                  : 'Commands',
              spacing: spacing,
              styles: styles,
              color: cs.onSurfaceVariant,
            ),
          );
        }
      }

      final selected = index == selectedIndex;
      final (icon, label, subtitle, experimental) = switch (suggestion) {
        ComposeTriggerFileSuggestion(:final candidate) => (
          candidate.isDirectory
              ? Icons.folder_outlined
              : Icons.description_outlined,
          candidate.insertText,
          candidate.relativePath,
          false,
        ),
        ComposeTriggerSlashSuggestion(:final candidate) => (
          candidate.kind == ComposeSlashCandidateKind.skill
              ? Icons.auto_awesome_outlined
              : Icons.terminal_outlined,
          candidate.insertText.trimRight(),
          candidate.kind == ComposeSlashCandidateKind.command
              ? _commandDetails(context, candidate)
              : candidate.subtitle,
          candidate.kind == ComposeSlashCandidateKind.command &&
              candidate.availability == NativeCommandAvailability.experimental,
        ),
      };

      children.add(
        TpHover(
          backgroundColor: selected
              ? cs.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          onTapDown: (_) => onSelected(suggestion),
          onTap: () => onSelected(suggestion),
          onHoverChanged: (_) => onHover(index),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.md,
              vertical: spacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: spacing.xs / 2),
                  child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: styles.smSemibold),
                      if ((subtitle != null && subtitle.trim().isNotEmpty) ||
                          experimental)
                        Wrap(
                          spacing: spacing.xs,
                          runSpacing: spacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (subtitle != null && subtitle.trim().isNotEmpty)
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: styles.smColored(cs.onSurfaceVariant),
                              ),
                            if (experimental)
                              TpStatusBadge(
                                label: context.l10n.composeCommandExperimental,
                                tone: TpStatusBadgeTone.warning,
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return children;
  }

  String? _commandDetails(
    BuildContext context,
    ComposeSlashCandidate candidate,
  ) {
    final l10n = context.l10n;
    final details = <String>[
      switch (candidate.source) {
        ComposeSlashCandidateSource.native => l10n.composeCommandNative,
        ComposeSlashCandidateSource.plugin => l10n.composeCommandPlugin,
        null => '',
      },
      if (candidate.subtitle?.trim().isNotEmpty == true)
        candidate.subtitle!.trim(),
      if (candidate.description case final description?)
        description.localized(context),
    ].where((detail) => detail.isNotEmpty).toList();
    return details.isEmpty ? null : details.join(' · ');
  }
}

extension _NativeCommandDescriptionL10n on NativeCommandDescription {
  String localized(BuildContext context) => switch (this) {
    NativeCommandDescription.goal => context.l10n.composeNativeCommandGoal,
    NativeCommandDescription.compact =>
      context.l10n.composeNativeCommandCompact,
    NativeCommandDescription.plan => context.l10n.composeNativeCommandPlan,
    NativeCommandDescription.help => context.l10n.composeNativeCommandHelp,
  };
}

class _ComposeTriggerSectionHeader extends StatelessWidget {
  const _ComposeTriggerSectionHeader({
    required this.label,
    required this.spacing,
    required this.styles,
    required this.color,
  });

  final String label;
  final TpSpacing spacing;
  final TpTextStyles styles;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.sm,
        spacing.md,
        spacing.xs,
      ),
      child: Text(label, style: styles.smSemiboldTrackColored(color)),
    );
  }
}
