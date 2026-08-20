import 'dart:async';

import '../../resource/contribution/prompt_document.dart';
import '../../resource/contribution/resource_origin.dart';
import '../../resource/providers/prompt_contribution_provider.dart';

/// One-sentence reminder to load the managed catalog skill and teampilot MCP.
final class CatalogPromptProvider implements PromptContributionProvider {
  const CatalogPromptProvider();

  static const promptSentence =
      'To install or manage TeamPilot skills, plugins, or MCP servers, load the teampilot-catalog skill and use the teampilot MCP. Do not install into ~/.claude.';

  @override
  String get providerId => 'teampilot-catalog';

  @override
  FutureOr<Iterable<PromptContribution>> provide(
    PromptProviderContext context,
  ) {
    return const [
      PromptContribution(
        id: 'teampilot-catalog',
        title: 'TeamPilot catalog',
        content: promptSentence,
        scope: PromptScope.global,
        mergeRole: PromptMergeRole.append,
        origin: ContributionOrigin(
          providerId: 'teampilot-catalog',
          kind: ResourceOriginKind.managed,
          sourceId: 'teampilot-catalog',
        ),
      ),
    ];
  }
}
