import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/skill.dart';
import '../../theme/app_markdown_style_sheet.dart';
import '../../utils/logging/logger.dart';
import '../../widgets/github_details_button.dart';
import '../../widgets/workspace_library_card.dart';

class SkillDetailView extends StatefulWidget {
  const SkillDetailView({
    super.key,
    required this.skill,
    required this.onBack,
    required this.loadMarkdown,
  });

  final Skill skill;
  final VoidCallback onBack;
  final Future<String?> Function(Skill skill) loadMarkdown;

  @override
  State<SkillDetailView> createState() => _SkillDetailViewState();
}

enum _SkillMdStatus { loading, ready, missing, error }

class _SkillDetailViewState extends State<SkillDetailView> {
  _SkillMdStatus _status = _SkillMdStatus.loading;
  String _body = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SkillDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.skill.id != widget.skill.id) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _status = _SkillMdStatus.loading);
    try {
      final text = await widget.loadMarkdown(widget.skill);
      if (!mounted) return;
      if (text == null) {
        setState(() => _status = _SkillMdStatus.missing);
        return;
      }
      setState(() {
        _body = text;
        _status = _SkillMdStatus.ready;
      });
    } catch (e, st) {
      appLogger.w('[skills] read SKILL.md failed: $e', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _status = _SkillMdStatus.error);
    }
  }

  void _onLinkTap(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      openGithubBrowseUrl(href);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return WorkspaceLibraryCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TpIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: l10n.back,
                size: TpIconButton.chromeAlignedSize(context),
                onTap: widget.onBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.skill.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).mdSemiboldColored(cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(child: _bodyFor(context, l10n)),
        ],
      ),
    );
  }

  Widget _bodyFor(BuildContext context, AppLocalizations l10n) {
    switch (_status) {
      case _SkillMdStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case _SkillMdStatus.missing:
        return TpEmptyState(
          icon: Icons.description_outlined,
          title: l10n.skillsDetailMissing,
          centered: true,
        );
      case _SkillMdStatus.error:
        return TpEmptyState(
          icon: Icons.error_outline,
          title: l10n.skillsDetailReadError,
          centered: true,
        );
      case _SkillMdStatus.ready:
        return SelectionArea(
          child: MarkdownDisplayModeScope(
            codeBlockMode: ContentDisplayMode.flatten,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: MarkdownView(
                    document: compileMarkdown(_body),
                    tokens: buildAppMarkdownTokens(
                      Theme.of(context),
                      MarkdownProfile.document,
                      width: constraints.maxWidth,
                    ),
                    resolvers: MarkdownResolvers(onLinkTap: _onLinkTap),
                  ),
                );
              },
            ),
          ),
        );
    }
  }
}
