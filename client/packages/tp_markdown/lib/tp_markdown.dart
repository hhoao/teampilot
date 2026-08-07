/// Semantic GFM markdown: compile → IR → kind-based Flutter [MarkdownView].
library tp_markdown;

export 'src/compile/content_compiler.dart';
export 'src/compile/content_truncate.dart';
export 'src/compile/streaming_markdown.dart';
export 'src/ir/markdown_block_kind.dart';
export 'src/ir/markdown_document.dart';
export 'src/markdown_display_mode_scope.dart';
export 'src/registry/block_widget_registry.dart';
export 'src/registry/markdown_resolvers.dart';
export 'src/render/inline_spans.dart' show forcedStrut;
export 'src/render/markdown_view.dart';
export 'src/render/virtual_markdown_view.dart';
export 'src/strings.dart';

export 'src/tokens/markdown_profile.dart';
export 'src/tokens/markdown_tokens.dart';
