# Patch: remove the Rust URL hint pass (engine does OSC 8 only)

> ⚠️ **UNVERIFIED ON WINDOWS.** This patch edits Rust in the `flutter_alacritty`
> submodule. It was authored on a Windows box that cannot compile the native
> engine, run `cargo test`, or rebuild the bundled library. **Apply, build, and
> test on Linux/macOS before committing.** Do not commit unbuilt.

## Why

URL detection now lives in the Dart `UrlLinkProvider` (shipped library default).
The engine still runs its own legacy URL auto-detect "hint pass" (`apply_hint_pass`),
so URLs are detected twice. It is idempotent (both set `FLAG_HYPERLINK` on the same
cells, OSC 8 wins), so this is purely a convergence cleanup — **no functional change**.
After this patch the engine handles only **OSC 8** hyperlinks (a real terminal
protocol); all text-scan link policy lives in the Dart link-provider seam.

## Scope / build impact

- **One file:** `client/packages/flutter_alacritty/packages/rust_lib_flutter_alacritty/rust/src/engine.rs`.
- **No FRB codegen needed.** `apply_hint_pass` is a private method and `hint_regex`
  is a private field of the opaque `TerminalEngine`; no `#[frb]`-exposed signature
  changes. You only need to rebuild the native lib (`cargo build` + `flutter build <platform>`).
- **Do NOT touch imports.** `RegexSearch`, `RegexIter`, `Direction`, `Match`,
  `point_in_match` are all still used by the **search** pass (engine.rs lines ~508–532).
  Only `RegexSearch::new(...)` for the hint regex goes away; the type stays (search uses it).

## Edits

### 1. Remove the `hint_regex` field

`struct TerminalEngine { ... }` (~line 226) — delete:
```rust
    hint_regex: Option<RegexSearch>,
```

### 2. Remove its construction + struct-init entry

In `TerminalEngine::new` (~line 260) delete:
```rust
        let hint_regex = RegexSearch::new(r"(?:https?|ftp|file)://[^\s]+").ok();
```
and in the `TerminalEngine { ... }` initializer (~line 275) delete:
```rust
            hint_regex,
```

### 3. Remove the three call sites

Delete each occurrence (lines ~534, ~906, ~956):
```rust
        self.apply_hint_pass(&mut update);
```
```rust
            self.apply_hint_pass(&mut u);
```
```rust
        self.apply_hint_pass(&mut u);
```
(Each is the line just before the function returns its `RenderUpdate`/`u`. Remove only
the `apply_hint_pass` call; keep the surrounding `update`/`u` return.)

### 4. Remove the `apply_hint_pass` method

Delete the whole method (~lines 538–595), beginning:
```rust
    /// URL auto-detect over the visible region; skips cells already hyperlinked (OSC 8).
    fn apply_hint_pass(&mut self, update: &mut RenderUpdate) {
        ...
    }
```
Keep `intern_hyperlink` and all OSC 8 hyperlink interning (separate, still used).

### 5. Update the Rust tests

In the `#[cfg(test)]` module:

- **Delete** `url_auto_detect_marks_visible_region` (~line 1447) and
  `url_auto_detect_applies_on_take_damage_path` (~line 1460) — they assert the
  removed auto-detect. (URL detection is now covered by Dart `url_link_provider_test.dart`.)
- **Repurpose** `osc8_wins_over_auto_detect_when_both_apply` (~line 1492): the premise
  (auto-detect competing with OSC 8) no longer exists. Either delete it (OSC 8 carry is
  already covered by `osc8_hyperlink_is_carried_on_cell_data`, ~line 1433) or rewrite it to
  assert that a **plain URL with no OSC 8 is NOT marked** `FLAG_HYPERLINK` by the engine:
  ```rust
  #[test]
  fn plain_url_is_not_auto_marked_by_engine() {
      // URL detection moved to the Dart UrlLinkProvider; the engine marks only OSC 8.
      let mut e = TerminalEngine::new(80, 24, EngineConfig::default());
      e.advance(b"see https://example.com here");
      let u = e.full_snapshot(); // or the snapshot fn the other tests use
      let any_hyperlink = u.lines.iter().flat_map(|l| l.cells.iter())
          .any(|c| c.flags & FLAG_HYPERLINK != 0);
      assert!(!any_hyperlink, "engine must not auto-mark plain URLs after hint-pass removal");
  }
  ```
  (Match the snapshot/advance helpers the neighboring tests use — `full_snapshot` /
  `full_snapshot_searched` / `take_damage`. Read the sibling tests for the exact shape.)

## Build & verify (Linux/macOS)

```bash
cd client/packages/flutter_alacritty/packages/rust_lib_flutter_alacritty/rust
cargo build
cargo test                         # the URL-hint tests are gone; OSC 8 tests still pass

cd ../../../../..                  # back to client/
flutter build linux --debug        # (or macos) rebuild the bundled native lib
flutter test --exclude-tags integration
cd packages/flutter_alacritty && flutter test
```

Expected: green. Then manually confirm in the app that a plain `https://…` printed in
the terminal is still clickable — now via the Dart `UrlLinkProvider`, not the engine —
and OSC 8 hyperlinks (e.g. `ls --hyperlink=auto`) still work.

## Commit (after it builds + tests pass)

```bash
# in the submodule
git -C client/packages/flutter_alacritty commit -am \
  "refactor(alacritty): remove URL hint pass; engine handles OSC 8 only"
# in the parent repo, bump the submodule pointer
git add client/packages/flutter_alacritty
git commit -m "chore: update flutter_alacritty submodule (engine OSC8-only links)"
```
