import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the GitHub (or other) browse URL in the system browser.
Future<void> openGithubBrowseUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Text button that opens a GitHub browse URL; hidden when [url] is null.
class GithubDetailsButton extends StatelessWidget {
  const GithubDetailsButton({
    required this.url,
    required this.label,
    super.key,
  });

  final String? url;
  final String label;

  @override
  Widget build(BuildContext context) {
    final target = url?.trim();
    if (target == null || target.isEmpty) {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      onPressed: () => openGithubBrowseUrl(target),
      icon: const Icon(Icons.open_in_new, size: AppIconSizes.md),
      label: Text(label),
    );
  }
}
