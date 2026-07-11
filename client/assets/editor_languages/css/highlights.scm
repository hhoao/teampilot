; Minimal CSS highlight captures for tree-sitter-css.

(comment) @comment

(tag_name) @tag
(nesting_selector) @tag
(universal_selector) @tag

(class_name) @property
(id_name) @property
(property_name) @property
(feature_name) @property
(attribute_name) @attribute

(function_name) @function

(string_value) @string
(color_value) @constant
(integer_value) @number
(float_value) @number
(unit) @type

(at_keyword) @keyword
(to) @keyword
(from) @keyword
(important) @keyword

[
  "~"
  ">"
  "+"
  "-"
  "*"
  "/"
  "="
  "^="
  "|="
  "~="
  "$="
  "*="
  "and"
  "or"
  "not"
  "only"
] @operator

[
  "#"
  ","
  ":"
  ";"
  "{"
  "}"
  "("
  ")"
] @punctuation
