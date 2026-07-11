; Minimal TOML highlight captures for tree-sitter-toml.

(bare_key) @property
(quoted_key) @property
(pair
  (bare_key)) @property

(boolean) @constant.builtin
(comment) @comment
(string) @string

[
  (integer)
  (float)
] @number

[
  (offset_date_time)
  (local_date_time)
  (local_date)
  (local_time)
] @constant

"=" @operator

[
  "."
  ","
] @punctuation

[
  "["
  "]"
  "[["
  "]]"
  "{"
  "}"
] @punctuation
