## Summary

This change replaces hot-path markdown rendering with a compile-to-IR path.

### Motivation

History fling frames were dominated by `MarkdownBody` and table layout.

### Changes

1. Add content IR types
2. Compile GFM via `package:markdown`
3. Cache prepared markdown documents

### Test plan

- [x] unit tests for headings and tables
- [ ] widget tests for links
- [ ] perf re-export vs baseline

See [design notes](https://example.com/design).
