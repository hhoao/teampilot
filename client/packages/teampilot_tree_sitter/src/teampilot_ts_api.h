#ifndef TEAMPILOT_TS_API_H
#define TEAMPILOT_TS_API_H

#include "tree_sitter/api.h"

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Returns a bundled tree-sitter language, statically linked into this asset.
//
// Wrapping each `tree_sitter_*` behind a stable `tp_`-prefixed symbol keeps the
// FFI surface independent of per-grammar symbol naming and lets ffigen bind a
// single header without pulling every grammar's generated declarations.
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_json(void);
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_dart(void);
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_yaml(void);
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_markdown(void);
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_python(void);
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_rust(void);
// The `tsx` grammar backs the `typescript` pack (parses .ts/.tsx/.js/.jsx).
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_typescript(void);
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_bash(void);
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_xml(void);
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_toml(void);
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_css(void);

#ifdef __cplusplus
}
#endif

#endif  // TEAMPILOT_TS_API_H
