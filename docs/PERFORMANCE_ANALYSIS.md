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
# Human-readable full report
dart run tool/analyze_performance_json.dart ~/Downloads/snapshot.json

# One-screen triage (best first pass for humans and AI)
dart run tool/analyze_performance_json.dart ~/Downloads/snapshot.json --format summary

# Machine-readable report (best for AI agents)
dart run tool/analyze_performance_json.dart ~/Downloads/snapshot.json --format json

# Drill into the slowest janky frame automatically
dart run tool/analyze_performance_json.dart ~/Downloads/snapshot.json --frame auto

# Focus on a specific widget / phase
dart run tool/analyze_performance_json.dart ~/Downloads/snapshot.json \
  --frame auto --filter RightToolsPanel --no-embedder \
  --format json --sections frames,drilldown
```

## CLI options

| Option | Description |
|--------|-------------|
| `--format <text\|json\|summary>` | Output format (default: `text`) |
| `--sections <list>` | Comma-separated: `meta`, `frames`, `rebuild`, `timeline`, `drilldown`, `compare`, `all` |
| `--frame <id\|auto>` | Frame drill-down; `auto` = slowest janky frame |
| `--top <n>` | Top N items in ranked lists (default: 25) |
| `--budget <ms>` | Jank threshold override (default: `1000 / displayRefreshRate`) |
| `--filter <pattern>` | Case-insensitive substring filter on slice/event names |
| `--category <Dart,Embedder>` | Filter timeline by Perfetto category |
| `--janky-only` | Frames section: list janky frames only (skip min/p50 stats) |
| `--worst-frames <n>` | Compact drill-down for top N janky frames |
| `--no-embedder` | Exclude Embedder track from timeline analysis |
| `--compare <baseline.json>` | Compare current file (candidate) vs another export (baseline) |
| `-h`, `--help` | Show help |

## Recommended AI workflow

Use a **two-pass** flow to limit tokens and avoid parsing raw DevTools JSON (multi‑MB `traceBinary`).

1. **Triage** — `--format summary`  
   Gets jank count, worst frames, bottleneck phase (build / raster / vsync), and top timeline slices.

2. **Drill-down** — `--format json` with filters  
   ```bash
   dart run tool/analyze_performance_json.dart snapshot.json \
     --format json \
     --frame auto \
     --no-embedder \
     --filter Panel \
     --sections frames,drilldown,rebuild
   ```

3. **Regression** — after a fix, compare against a baseline export:  
   ```bash
   dart run tool/analyze_performance_json.dart after.json \
     --compare before.json \
     --format json \
     --sections compare,frames
   ```

Prefer `--format json` over pasting the raw DevTools export into chat. Prefer `--sections` to omit unused blocks (`timeline` is the largest).

## What the tool analyzes

| Snapshot field | Analysis |
|----------------|----------|
| `flutterFrames` | Jank list, build/raster/vsync stats, bottleneck hint |
| `displayRefreshRate` | Default frame budget (e.g. 240 Hz → ~4.17 ms) |
| `traceBinary` | Perfetto slices, instants, shader events, CPU samples (if present) |
| `rebuildCountModel` | Top widgets by rebuild count; per-frame rebuilds in drill-down |
| `selectedFrameId` | Default frame for drill-down when `--frame` omitted |
| `selectedTab` | Which DevTools tab was active at export |

## What it does not replace

- Interactive **Perfetto UI** in DevTools (zoom, pan, full flame chart)
- Live recording or continuous profiling
- Full parity with DevTools **Frame Analysis** UI (exact UI/Raster event tree linking)

The tool targets **offline triage**: which frames jank, which phase, which widget/event names dominate.

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
    ├── trace_filters.dart                 # --filter, --category, --no-embedder
    ├── report_printer.dart                # --format text
    ├── report_json.dart                    # --format json
    └── report_summary.dart                # --format summary
```

To extend analysis, add logic in `analyzer.dart` and new fields on `PerformanceAnalysisResult`; keep `analyze_performance_json.dart` as a thin CLI.

## Related docs

- [DEBUGGING.md](DEBUGGING.md) — general bug investigation (search-first, root cause)
- [DEVELOPMENT.md](DEVELOPMENT.md) — clone, `flutter run`, tests
