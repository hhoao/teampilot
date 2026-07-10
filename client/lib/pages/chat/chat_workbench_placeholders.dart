import 'package:flutter/material.dart';

import '../../theme/app_text_styles.dart';

class ChatWorkbenchSessionLoadingView extends StatelessWidget {
  const ChatWorkbenchSessionLoadingView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;
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
