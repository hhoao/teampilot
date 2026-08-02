# Flutter SDK patches

TeamPilot may ship small **mandatory** Flutter framework patches until the
corresponding changes land upstream. Patches live under
[`tool/flutter_patches/`](../tool/flutter_patches/) and are applied by a single
idempotent script (local + CI).

## Apply (required)

After installing or upgrading Flutter:

```bash
# from repo root
./tool/flutter_patches/apply_flutter_patches.sh
```

- Resolves the SDK via `FLUTTER_ROOT`, `flutter sdk-path`, or the `flutter` binary.
- Applies every `tool/flutter_patches/*.patch` in **sorted** filename order.
- Skips a patch when `git apply --reverse --check` succeeds (already applied).
- Exits non-zero if a patch no longer matches the SDK (refresh the `.patch`).

CI runs the same step after `flutter-action` via
[`.github/actions/apply-flutter-patches`](../.github/actions/apply-flutter-patches/action.yml)
(`client-verify.yml`, `release.yml`).

## Add a patch

1. Edit your local Flutter SDK on the **same stable revision** CI uses.
2. From the Flutter SDK root, export a unified diff:

   ```bash
   git diff -- path/to/changed/files \
     > /path/to/teampilot/tool/flutter_patches/<name>.patch
   ```

3. Prefer a descriptive `<name>` (e.g. `selection_height_style.patch`).
4. Commit only the `.patch` in teampilot. **Do not** change the apply script or
   CI unless you are changing the apply mechanism itself.
5. Re-run `./tool/flutter_patches/apply_flutter_patches.sh` and verify analyze/tests.

## Refresh after Flutter upgrades

When `apply` fails with “does not apply cleanly”:

1. Reset or reinstall a clean Flutter SDK at the new revision.
2. Re-implement the change (or `git cherry-pick` / re-edit).
3. Re-export the `.patch` with `git diff` as above.
4. Commit the updated patch file.

## Current patches

| Patch | Purpose | Upstream |
|-------|---------|----------|
| `selection_height_style.patch` | `DefaultSelectionStyle.selectionHeightStyle`; Theme/MaterialApp forward it; paint uses ambient style (tight→Middle); join wrap seams without widening short lines | [flutter#161010](https://github.com/flutter/flutter/issues/161010) |

When an upstream fix ships on **stable**, delete that `.patch` and drop any
app-only wrappers that existed solely for the workaround (if no longer needed).

## App wiring

Product code that **requires** a patched API must fail to compile without the
patch (no silent fallback). Example: chat / markdown preview uses
`AiLineSpacedSelectionStyle`, which sets
`DefaultSelectionStyle.selectionHeightStyle` to
`BoxHeightStyle.includeLineSpacingMiddle` (balanced line-spacing vs top-biased).
