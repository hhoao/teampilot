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

// Returns the tree-sitter JSON language, statically linked into this asset.
//
// Wrapping `tree_sitter_json` behind a stable `tp_`-prefixed symbol keeps the
// FFI surface independent of per-grammar symbol naming and lets ffigen bind a
// single header without pulling every grammar's generated declarations.
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_json(void);

#ifdef __cplusplus
}
#endif

#endif  // TEAMPILOT_TS_API_H
