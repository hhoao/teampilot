import '../models/skill.dart';

/// Parsed GitHub repository coordinates from a repository URL.
class ParsedGithubRepo {
  const ParsedGithubRepo({required this.owner, required this.name});
  final String owner;
  final String name;
}

/// Canonical display URL for a configured repo.
String formatGithubRepoUrl(SkillRepo repo) =>
    'https://github.com/${repo.owner}/${repo.name}';

/// Parses `https://github.com/owner/name` (optional `.git`, optional trailing slash).
///
/// Does not accept `owner/name` shorthand — use a full GitHub URL only.
ParsedGithubRepo? parseGithubRepoUrl(String url) {
  var cleaned = url.trim();
  if (cleaned.isEmpty) return null;

  final uri = Uri.tryParse(cleaned);
  if (uri != null && uri.hasScheme) {
    if (uri.host != 'github.com' && uri.host != 'www.github.com') {
      return null;
    }
    cleaned = uri.path;
  } else {
    return null;
  }

  cleaned = cleaned.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
  if (cleaned.endsWith('.git')) {
    cleaned = cleaned.substring(0, cleaned.length - 4);
  }

  final parts = cleaned.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.length != 2) return null;

  return ParsedGithubRepo(owner: parts[0], name: parts[1]);
}
