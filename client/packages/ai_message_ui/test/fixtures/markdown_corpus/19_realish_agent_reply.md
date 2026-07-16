# Investigation notes

I inspected the failing suite and found two issues:

- nested lists were losing task state
- fenced code language tags were dropped

## Proposed fix

Use GFM extension set and map `pre > code.language-*` into `CodeBlock`.

```bash
cd client/packages/ai_message_ui
flutter test test/content_compiler_test.dart
```

### Follow-ups

1. corpus gate ≥95%
2. LRU cache (max 64)
3. renderer switch in `AiTextPartView`

---

Ready for review when green.
