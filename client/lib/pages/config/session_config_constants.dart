const kSessionPathPersistDebounce = Duration(milliseconds: 400);

/// Team sessions use the app-level provider catalog's flashskyai LLM config
/// file; per-session LLM path override is not exposed.
const kShowLlmConfigPathSetting = false;
