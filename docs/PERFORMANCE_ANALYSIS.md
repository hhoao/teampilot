# Performance snapshot analysis

Offline CLI for Flutter **DevTools Performance** JSON exports. Use it to triage jank (slow frames), timeline hotspots, widget rebuild stats, and regressions between two recordings — especially when handing traces to an AI assistant.

**Entry point:** `client/tool/analyze_performance_json.dart`  
**Run from:** `client/` (requires `vm_service_protos` dev dependency)

```bash
cd client
dart run tool/analyze_performance_json.dart /path/to/snapshot.json [options]
```

## Capture a snapshot

1. Open **Flutter DevTools → Performance** while the app is running (profile or debug).
2. Reproduce the jank (e.g. open a tab, resize a panel).
3. Click **Export** (upper-right of the frame chart).
4. Save the `.json` file. Only exports originally produced by DevTools are supported.

Optional: enable **Rebuild Stats** in DevTools before recording if you need `rebuildCountModel` in the export (widget rebuild counts per frame).

### Automated capture (integration test)

A first scenario covers **app startup → open two workspace tabs → switch between them**. It records frame timings + Perfetto timeline via the in-process VM service and writes DevTools-compatible JSON.

```bash
cd client
dart run tool/run_workspace_switch_performance.dart
# optional: --output /tmp/perf.json
```

This runs `integration_test/workspace_switch_performance_test.dart` (tag `performance`), saves `build/perf_workspace_switch.json` by default, then prints a **summary** report.

**Notes:**

- Runs in **debug** integration-test mode (not profile) — absolute frame times are higher than production; use for **hotspot discovery** and **before/after regressions** on the same harness.
- Scenario uses fake terminals (no real CLI PTY) to keep runs repeatable.
- Re-analyze manually: `dart run tool/analyze_performance_json.dart build/perf_workspace_switch.json --frame auto --format json`


```bash
# One-screen triage (AI / human first pass — hot paths + jank stats)
dart run tool/analyze_performance_json.dart ~/Downloads/snapshot.json --format summary

# Machine-readable full report
dart run tool/analyze_performance_json.dart ~/Downloads/snapshot.json --format json

# Drill into the slowest janky frame
dart run tool/analyze_performance_json.dart ~/Downloads/snapshot.json --frame auto

# Focus on a specific widget / phase
dart run tool/analyze_performance_json.dart ~/Downloads/snapshot.json \
  --frame auto --filter RightToolsPanel --no-embedder \
  --format json --sections frames,drilldown,precision
```

## CLI options

| Option | Description |
|--------|-------------|
| `--format <text\|json\|summary\|flame-tree\|flame-tree-json>` | Output format (default: `text`; `summary` = jank + precision hot paths, excludes Embedder by default) |
| `--sections <list>` | Comma-separated: `meta`, `frames`, `rebuild`, `timeline`, `drilldown`, `precision`, `compare`, `all` |
| `--frame <id\|auto>` | Frame drill-down; `auto` = slowest janky frame |
| `--top <n>` | Top N items in ranked lists (default: 25) |
| `--budget <ms>` | Jank threshold override (default: `1000 / displayRefreshRate`) |
| `--filter <pattern>` | Case-insensitive substring filter on slice/event names |
| `--category <Dart,Embedder>` | Filter timeline by Perfetto category |
| `--janky-only` | Frames section: list janky frames only (skip min/p50 stats) |
| `--worst-frames <n>` | Compact drill-down for top N janky frames |
| `--precision-frames <n>` | Janky frames used for hot-path aggregation and rebuild correlation (default: 5) |
| `--no-embedder` | Exclude Embedder track (default when `--format summary`) |
| `--embedder` | Include Embedder slices with `--format summary` |
| `--compare <baseline.json>` | Compare current file (candidate) vs another export (baseline) |
| `-h`, `--help` | Show help |

## Recommended AI workflow

Avoid pasting raw DevTools JSON (multi‑MB `traceBinary`). Prefer the CLI.

1. **Triage** — `--format summary`  
   Jank count, worst frames, **aggregated UI hot paths** (widget breadcrumbs), rebuild ↔ slice matches when captured, and which track (`ui` / `raster`) to inspect per frame. Embedder timeline noise is excluded by default.

2. **Structured drill-down** — `--format json`  
   ```bash
   dart run tool/analyze_performance_json.dart snapshot.json \
     --format json \
     --no-embedder \
     --sections precision,frames,drilldown
   ```
   Full `precision` object: `frameGuides`, `uiHotPaths`, `rasterHotPaths`, `dartMethodHotspots`, `dartHotPaths`, `rebuildCorrelations`, unmatched slices/rebuilds.

3. **Regression** — after a fix, compare against a baseline export:  
   ```bash
   dart run tool/analyze_performance_json.dart after.json \
     --compare before.json \
     --format json \
     --sections compare,frames
   ```

4. **Flame tree** — nested BUILD/LAYOUT hierarchy with **self time** (closest to DevTools flame chart):  
   ```bash
   dart run tool/analyze_performance_json.dart snapshot.json \
     --format flame-tree --frame auto --no-embedder
   dart run tool/analyze_performance_json.dart snapshot.json \
     --format flame-tree-json --frame 1515
   ```
   Per-level pruning: `--tree-top 2` (default for flame-tree) keeps top N children by self ms at each level and recurses; `--tree-full` shows the full tree. `topSelfTime` is from the full tree before pruning.

Prefer `--format json` over pasting the raw DevTools export into chat. Prefer `--sections` to omit unused blocks (`timeline` is the largest).

## What the tool analyzes

| Snapshot field | Analysis |
|----------------|----------|
| `flutterFrames` | Jank list, build/raster/vsync stats, bottleneck hint |
| `displayRefreshRate` | Default frame budget (e.g. 240 Hz → ~4.17 ms) |
| `traceBinary` | Perfetto slices; may cover **fewer** frames than `flutterFrames` (see `traceCoverage` in `precision`). Summary labels which frames hot paths include and which janky frames lack timeline data. |
| `traceBinary` + `--format flame-tree` | Nested slice tree on `io.flutter.ui` **and Dart-track** render methods with **total/self ms** |
| `rebuildCountModel` | Top widgets by rebuild count; per-frame rebuilds; **rebuild ↔ slice correlation** in `precision` |
| `selectedFrameId` | Default frame for drill-down when `--frame` omitted |
| `selectedTab` | Which DevTools tab was active at export |

## What it does not replace

- Interactive **Perfetto UI** in DevTools (zoom, pan, full flame chart)
- Live recording or continuous profiling
- Full parity with DevTools **Frame Analysis** UI (exact UI/Raster event tree linking)

The tool targets **offline triage**: which frames jank, which phase, which widget/event names dominate.

### UI widget tree vs Dart method slices

DevTools shows two related but distinct timelines:

- **`io.flutter.ui`** — widget breadcrumbs (`BUILD` → `RightToolsPanel` → …)
- **`Dart` track** — render-object method slices (`RenderParagraph.getDryLayout`, `RenderIndexedStack.performLayout`, …)

The widest bar in DevTools is often a **Dart method** slice, not a named widget in the UI tree. `precision.dartMethodHotspots` and flame-tree output include these; rebuild correlation links widgets like `Text` to `RenderParagraph.*` when possible.

## Code layout

```
client/tool/
├── analyze_performance_json.dart          # CLI entry
└── performance_snapshot/
    ├── cli_args.dart                      # Argument parsing
    ├── options.dart                       # AnalyzeOptions, ReportSection, OutputFormat
    ├── snapshot_loader.dart               # JSON → PerformanceSnapshot
    ├── analyzer.dart                      # analyzeSnapshot() → PerformanceAnalysisResult
    ├── models.dart                        # Report data types
    ├── rebuild_model.dart                 # rebuildCountModel decoder
    ├── trace_decoder.dart                 # Perfetto traceBinary decoder
    ├── frame_slice_tree.dart                # UI/raster/dart slice trees + bottleneck helpers
    ├── dart_slice_analysis.dart             # Dart-track RenderObject method hotspots
    ├── precision_analysis.dart              # hot-path aggregation + rebuild correlation
    ├── slice_tree.dart                    # Nested slice tree + self-time
    ├── flame_tree_builder.dart            # Per-frame flame tree
    ├── report_flame_tree.dart             # --format flame-tree output
    ├── trace_filters.dart                 # --filter, --category, --no-embedder
    ├── report_printer.dart                # --format text
    ├── report_json.dart                    # --format json
    ├── report_summary.dart                # --format summary (precision highlights)
    ├── summary_format.dart              # hot-path shortening for summary
```

To extend analysis, add logic in `analyzer.dart` and new fields on `PerformanceAnalysisResult`; keep `analyze_performance_json.dart` as a thin CLI.

## Related docs

- [DEBUGGING.md](DEBUGGING.md) — general bug investigation (search-first, root cause)
- [DEVELOPMENT.md](DEVELOPMENT.md) — clone, `flutter run`, tests
