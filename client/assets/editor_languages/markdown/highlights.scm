; Minimal Markdown (block) highlight captures for tree-sitter-markdown.

(atx_heading
  (inline) @function)
(setext_heading
  (paragraph) @function)

[
  (atx_h1_marker)
  (atx_h2_marker)
  (atx_h3_marker)
  (atx_h4_marker)
  (atx_h5_marker)
  (atx_h6_marker)
  (setext_h1_underline)
  (setext_h2_underline)
] @keyword

[
  (indented_code_block)
  (fenced_code_block)
] @string

(fenced_code_block_delimiter) @punctuation

[
  (list_marker_plus)
  (list_marker_minus)
  (list_marker_star)
  (list_marker_dot)
  (list_marker_parenthesis)
  (thematic_break)
] @punctuation

(block_quote) @comment
