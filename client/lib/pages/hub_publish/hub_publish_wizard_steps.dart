import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_text_styles.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../../services/hub_publish/hub_publish_record_store.dart';
import '../../widgets/textarea/app_textarea.dart';

/// Auth step: GitHub token from store or paste.
class HubPublishAuthStep extends StatelessWidget {
  const HubPublishAuthStep({
    super.key,
    required this.tokenController,
    required this.hasStoredToken,
  });

  final TextEditingController tokenController;
  final bool hasStoredToken;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const Key('hub-publish-auth'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.hubPublishAuthHint),
        const SizedBox(height: 12),
        if (hasStoredToken) ...[
          Text(
            l10n.hubPublishTokenStored,
            style: AppTextStyles.of(context).mutedSm,
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          key: const Key('hub-publish-token'),
          controller: tokenController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.hubPublishTokenLabel,
            hintText: l10n.hubPublishTokenHint,
          ),
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }
}

/// Metadata step: slug, name, description, category, author; tags for experts.
class HubPublishMetadataStep extends StatelessWidget {
  const HubPublishMetadataStep({
    super.key,
    required this.kind,
    required this.slugController,
    required this.nameController,
    required this.descriptionController,
    required this.categoryController,
    required this.authorController,
    required this.tagsController,
  });

  final HubPublishKind kind;
  final TextEditingController slugController;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController categoryController;
  final TextEditingController authorController;
  final TextEditingController tagsController;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isExpert = kind == HubPublishKind.expert;
    return Column(
      key: const Key('hub-publish-metadata'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('hub-publish-slug'),
          controller: slugController,
          decoration: InputDecoration(
            labelText: l10n.hubPublishSlugLabel,
            hintText: l10n.hubPublishSlugHint,
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('hub-publish-name'),
          controller: nameController,
          decoration: InputDecoration(labelText: l10n.name),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (context) {
            final bodyStyle =
                Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
            return AppTextarea(
              key: const Key('hub-publish-description'),
              controller: descriptionController,
              decoration: InputDecoration(
                labelText: l10n.expertEditorDescription,
              ),
              minHeight: appTextareaHeightForLines(bodyStyle, lines: 2),
              maxHeight: appTextareaHeightForLines(bodyStyle, lines: 4),
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('hub-publish-category'),
          controller: categoryController,
          decoration: InputDecoration(labelText: l10n.expertEditorCategory),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('hub-publish-author'),
          controller: authorController,
          decoration: InputDecoration(labelText: l10n.hubPublishAuthorLabel),
          textInputAction: TextInputAction.next,
        ),
        if (isExpert) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('hub-publish-tags'),
            controller: tagsController,
            decoration: InputDecoration(
              labelText: l10n.expertEditorTags,
              hintText: l10n.expertEditorTagsHint,
            ),
          ),
        ],
      ],
    );
  }
}

/// Team-only gates: remap local experts; list non-portable deps.
class HubPublishGatesStep extends StatelessWidget {
  const HubPublishGatesStep({
    super.key,
    required this.localExpertKeys,
    required this.nonPortableIds,
    required this.remap,
    required this.candidates,
    required this.onRemapChanged,
  });

  final List<String> localExpertKeys;
  final List<String> nonPortableIds;
  final Map<String, String> remap;
  final List<DiscoverableMember> candidates;
  final void Function(String localKey, String publishedKey) onRemapChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const Key('hub-publish-gates'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (localExpertKeys.isNotEmpty) ...[
          Text(
            key: const Key('hub-publish-local-expert-blocked'),
            l10n.hubPublishLocalExpertHint,
          ),
          const SizedBox(height: 12),
          for (final localKey in localExpertKeys) ...[
            Text(
              localKey,
              style: AppTextStyles.of(context).mutedSm,
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              key: Key('hub-publish-remap-$localKey'),
              // ignore: deprecated_member_use
              value: remap[localKey],
              decoration: InputDecoration(
                labelText: l10n.hubPublishRemapLabel,
              ),
              items: [
                for (final candidate in candidates)
                  DropdownMenuItem(
                    value: candidate.key,
                    child: Text(candidate.name),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                onRemapChanged(localKey, value);
              },
            ),
            const SizedBox(height: 12),
          ],
        ],
        if (nonPortableIds.isNotEmpty) ...[
          Text(
            key: const Key('hub-publish-non-portable'),
            l10n.hubPublishNonPortableHint,
            style: AppTextStyles.of(context).mdColored(cs.error),
          ),
          const SizedBox(height: 8),
          for (final id in nonPortableIds)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $id'),
            ),
        ],
        if (localExpertKeys.isEmpty && nonPortableIds.isEmpty)
          Text(l10n.hubPublishGatesClear),
      ],
    );
  }
}

/// Confirm summary before calling publish.
class HubPublishConfirmStep extends StatelessWidget {
  const HubPublishConfirmStep({
    super.key,
    required this.kind,
    required this.slug,
    required this.name,
    required this.category,
    required this.author,
    required this.error,
    required this.busy,
  });

  final HubPublishKind kind;
  final String slug;
  final String name;
  final String category;
  final String author;
  final String? error;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const Key('hub-publish-confirm'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.hubPublishConfirmHint),
        const SizedBox(height: 12),
        _row(context, l10n.hubPublishSlugLabel, slug),
        _row(context, l10n.name, name),
        if (category.isNotEmpty)
          _row(context, l10n.expertEditorCategory, category),
        if (author.isNotEmpty) _row(context, l10n.hubPublishAuthorLabel, author),
        _row(
          context,
          l10n.hubPublishKindLabel,
          kind == HubPublishKind.expert
              ? l10n.hubPublishKindExpert
              : l10n.hubPublishKindTeam,
        ),
        if (busy) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            key: const Key('hub-publish-error'),
            style: AppTextStyles.of(context).mdColored(cs.error),
          ),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTextStyles.of(context).mdSemibold,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// Success step showing the opened PR URL.
class HubPublishSuccessStep extends StatelessWidget {
  const HubPublishSuccessStep({
    super.key,
    required this.prUrl,
    required this.onCopy,
    required this.onOpen,
  });

  final String prUrl;
  final VoidCallback onCopy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const Key('hub-publish-success'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.hubPublishSuccessHint),
        const SizedBox(height: 12),
        SelectableText(
          prUrl,
          key: const Key('hub-publish-pr-url'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 18),
              label: Text(l10n.hubPublishCopyLink),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l10n.hubPublishOpenPr),
            ),
          ],
        ),
      ],
    );
  }
}
