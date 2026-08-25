#ifndef TEAMPILOT_SEARCH_H
#define TEAMPILOT_SEARCH_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TpSearchHandle TpSearchHandle;

typedef struct TpSearchConfig {
  const char* root;
  const char* pattern;
  int32_t is_regex;
  int32_t case_sensitive;
  int32_t smart_case;
  int32_t use_gitignore;
  const char* const* files_to_include;
  uint32_t files_to_include_count;
  const char* const* files_to_exclude;
  uint32_t files_to_exclude_count;
  uint64_t max_file_size;
  uint64_t max_results;
  uint32_t max_chunk_matches;
  uint32_t max_chunk_bytes;
} TpSearchConfig;

typedef struct TpSearchMatch {
  const char* path;
  const char* relative_path;
  uint64_t line_number;
  const char* line_text;
  uint32_t match_start;
  uint32_t match_end;
} TpSearchMatch;

typedef struct TpSearchChunk {
  char* string_buf;
  uint32_t string_buf_cap;
  uint32_t string_buf_len;
  TpSearchMatch* matches;
  uint32_t matches_cap;
  uint32_t matches_len;
  int32_t truncated;
} TpSearchChunk;

const char* tp_search_version(void);
int32_t tp_search_new(const TpSearchConfig* config, TpSearchHandle** out);
int32_t tp_search_next(TpSearchHandle* handle, TpSearchChunk* chunk);
void tp_search_cancel(TpSearchHandle* handle);
void tp_search_free(TpSearchHandle* handle);

typedef struct TpFileIndexHandle TpFileIndexHandle;

typedef struct TpFileIndexConfig {
  const char* root;
  int32_t use_gitignore;
  uint64_t max_entries;
  uint32_t max_chunk_matches;
  uint32_t max_chunk_bytes;
} TpFileIndexConfig;

typedef struct TpFileIndexEntry {
  const char* path;
  const char* relative_path;
  const char* name;
} TpFileIndexEntry;

typedef struct TpFileIndexChunk {
  char* string_buf;
  uint32_t string_buf_cap;
  uint32_t string_buf_len;
  TpFileIndexEntry* entries;
  uint32_t entries_cap;
  uint32_t entries_len;
  int32_t truncated;
} TpFileIndexChunk;

int32_t tp_file_index_new(const TpFileIndexConfig* config, TpFileIndexHandle** out);
int32_t tp_file_index_build(TpFileIndexHandle* handle);
int32_t tp_file_index_build_start(TpFileIndexHandle* handle);
int32_t tp_file_index_build_poll(TpFileIndexHandle* handle);
void tp_file_index_cancel(TpFileIndexHandle* handle);
int32_t tp_file_index_query(TpFileIndexHandle* handle, const char* query, int32_t mode, uint32_t limit, TpFileIndexChunk* chunk);
int32_t tp_file_index_query_dirs(TpFileIndexHandle* handle, const char* query, uint32_t limit, TpFileIndexChunk* chunk);
void tp_file_index_free(TpFileIndexHandle* handle);

#ifdef __cplusplus
}
#endif
#endif
