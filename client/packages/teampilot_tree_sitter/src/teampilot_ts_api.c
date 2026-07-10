#include "teampilot_ts_api.h"

// Provided by the vendored tree-sitter-json generated parser (parser.c).
extern const TSLanguage *tree_sitter_json(void);

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_json(void) {
  return tree_sitter_json();
}
