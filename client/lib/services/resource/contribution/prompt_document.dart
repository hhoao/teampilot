import 'resource_origin.dart';

/// Scope used to compare prompt contribution precedence.
enum PromptScope { cli, member, team, expert, workspace, global }

/// How a prompt contribution participates in the neutral document.
enum PromptMergeRole { replace, append, section }

/// A target-neutral prompt contribution with stable provenance.
class PromptContribution {
  const PromptContribution({
    required this.id,
    required this.title,
    required this.content,
    this.scope = PromptScope.cli,
    this.mergeRole = PromptMergeRole.replace,
    required this.origin,
  });

  final String id;
  final String title;
  final String content;
  final PromptScope scope;
  final PromptMergeRole mergeRole;
  final ContributionOrigin origin;
}

/// The canonical, ordered prompt document produced by the assembler.
class PromptDocument {
  PromptDocument(Iterable<PromptSection> sections)
    : sections = List.unmodifiable(sections);

  const PromptDocument.empty() : sections = const [];

  final List<PromptSection> sections;

  List<PromptContribution> get contributions => [
    for (final section in sections) ...section.contributions,
  ];

  String get content => sections
      .map((section) => section.content.trim())
      .where((content) => content.isNotEmpty)
      .join('\n\n');
}

/// A final document section. Grouping retains every contribution and origin.
class PromptSection {
  PromptSection({
    required this.id,
    required this.title,
    required this.scope,
    required Iterable<PromptContribution> contributions,
  }) : contributions = List.unmodifiable(contributions);

  final String id;
  final String title;
  final PromptScope scope;
  final List<PromptContribution> contributions;

  String get content => contributions
      .map((contribution) => contribution.content.trim())
      .where((content) => content.isNotEmpty)
      .join('\n\n');
}
