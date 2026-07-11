#include "teampilot_ts_api.h"

// Provided by each vendored grammar's generated parser (parser.c).
extern const TSLanguage *tree_sitter_json(void);
extern const TSLanguage *tree_sitter_dart(void);
extern const TSLanguage *tree_sitter_yaml(void);
extern const TSLanguage *tree_sitter_markdown(void);
extern const TSLanguage *tree_sitter_python(void);
extern const TSLanguage *tree_sitter_rust(void);
extern const TSLanguage *tree_sitter_tsx(void);
extern const TSLanguage *tree_sitter_bash(void);
extern const TSLanguage *tree_sitter_xml(void);
extern const TSLanguage *tree_sitter_toml(void);
extern const TSLanguage *tree_sitter_css(void);

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_json(void) {
  return tree_sitter_json();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_dart(void) {
  return tree_sitter_dart();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_yaml(void) {
  return tree_sitter_yaml();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_markdown(void) {
  return tree_sitter_markdown();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_python(void) {
  return tree_sitter_python();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_rust(void) {
  return tree_sitter_rust();
}

// The `tsx` grammar is a superset that also parses .ts / .js / .jsx.
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_typescript(void) {
  return tree_sitter_tsx();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_bash(void) {
  return tree_sitter_bash();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_xml(void) {
  return tree_sitter_xml();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_toml(void) {
  return tree_sitter_toml();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_css(void) {
  return tree_sitter_css();
}
