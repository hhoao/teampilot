# gstack Requirement Dev Team Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `gstack-req-dev` Team Hub template and a new `gstack-developer` Expert Hub persona so users can clone a five-seat day-to-day requirement delivery team.

**Architecture:** Catalog-only change. No Flutter code. New `member.json` + `team.json` follow existing gstack hub shapes; indexes register the new slugs. Skills stay on experts (`skillDeps`); the team roster only references `expertKey`s.

**Tech Stack:** JSON hub registries (`member-hub/`, `team-hub/`), `DiscoverableMember` / `DiscoverableTeam` schemas.

**Spec:** `docs/superpowers/specs/2026-08-04-gstack-req-dev-team-design.md`

---

## File map

| Path | Action |
|------|--------|
| `member-hub/members/gstack-developer/member.json` | Create |
| `member-hub/index.json` | Add `"gstack-developer"` |
| `team-hub/teams/gstack-req-dev/team.json` | Create |
| `team-hub/index.json` | Add `{ "slug": "gstack-req-dev" }` |

---

### Task 1: Add `gstack-developer` expert

**Files:**
- Create: `member-hub/members/gstack-developer/member.json`
- Modify: `member-hub/index.json`

- [ ] **Step 1: Create `member.json`**

```json
{
  "name": "gstack Developer",
  "description": "Senior implementer: ship against the eng plan; self-review with /review; root-cause with /investigate before speculative fixes.",
  "category": "Development",
  "author": "gstack",
  "updatedAt": 1784764800000,
  "member": {
    "name": "developer",
    "responsibilities": "Implement against an approved eng plan; small commits; self-review before handoff; investigate before speculative fixes. Do not expand scope, replace QA acceptance, or own release.",
    "playbook": "Follow the gstack /review and /investigate skill methodology when available. Prefer the installed skill pack over improvising a parallel process.",
    "capabilities": []
  },
  "skillDeps": [
    {
      "id": "garrytan/gstack:review",
      "packId": "garrytan/gstack",
      "name": "Staff Review",
      "repoOwner": "garrytan",
      "repoName": "gstack",
      "repoBranch": "main",
      "directory": "review"
    },
    {
      "id": "garrytan/gstack:investigate",
      "packId": "garrytan/gstack",
      "name": "Investigate",
      "repoOwner": "garrytan",
      "repoName": "gstack",
      "repoBranch": "main",
      "directory": "investigate"
    }
  ],
  "i18n": {
    "zh": {
      "name": "gstack 开发者",
      "description": "高级实现者：按工程计划交付；用 /review 自审；没有调查前不做投机式修复。",
      "category": "开发",
      "member": {
        "responsibilities": "按已批准的工程计划实现；小步提交；交接前自审；投机式修复前先调查。不擅自扩 scope，不替代 QA 验收，不负责发版。",
        "playbook": "有 gstack /review、/investigate skill 时优先遵循其方法；优先使用已安装的 skill pack，勿另起一套并行流程。"
      }
    }
  }
}
```

- [ ] **Step 2: Register in `member-hub/index.json`**

Add `"gstack-developer"` to the `members` array (after `gstack-debugger` or with other gstack slugs — order not semantically required; keep gstack cluster together, e.g. after `gstack-debugger`).

- [ ] **Step 3: Validate member JSON parses**

From `client/`:

```bash
dart -e '
import "dart:convert";
import "dart:io";
import "package:teampilot/models/discoverable_member.dart";
void main() {
  final raw = jsonDecode(File("../member-hub/members/gstack-developer/member.json").readAsStringSync()) as Map;
  raw["key"] = "hhoao/teampilot/member-hub/gstack-developer";
  final m = DiscoverableMember.fromJson(raw.cast<String, Object?>());
  assert(m.skillDeps.length == 2);
  assert(m.member.name == "developer");
  print("ok member");
}
'
```

If `dart -e` is unavailable in this environment, instead run a one-off test file or:

```bash
python3 -c 'import json; json.load(open("member-hub/members/gstack-developer/member.json")); print("ok")'
```

and rely on Task 3 schema check via Flutter test helper if present.

Expected: parse succeeds; two skillDeps with `packId` `garrytan/gstack`.

- [ ] **Step 4: Commit** (only if user asked to commit)

```bash
git add member-hub/members/gstack-developer/member.json member-hub/index.json
git commit -m "$(cat <<'EOF'
feat(member-hub): add gstack-developer expert

EOF
)"
```

---

### Task 2: Add `gstack-req-dev` team template

**Files:**
- Create: `team-hub/teams/gstack-req-dev/team.json`
- Modify: `team-hub/index.json`

- [ ] **Step 1: Create `team.json`**

```json
{
  "key": "hhoao/teampilot/team-hub/gstack-req-dev",
  "name": "gstack Requirement Dev",
  "description": "Day-to-day requirement delivery: product framing → architecture → implementation (self-review + investigate) → QA → release.",
  "category": "Development",
  "author": "gstack",
  "updatedAt": 1784764800000,
  "cli": "claude",
  "teamMode": "native",
  "roster": [
    {
      "id": "team-lead",
      "expertKey": "hhoao/teampilot/member-hub/gstack-office-hours"
    },
    {
      "id": "architect",
      "expertKey": "hhoao/teampilot/member-hub/gstack-eng-manager"
    },
    {
      "id": "developer",
      "expertKey": "hhoao/teampilot/member-hub/gstack-developer"
    },
    {
      "id": "qa",
      "expertKey": "hhoao/teampilot/member-hub/gstack-qa"
    },
    {
      "id": "release",
      "expertKey": "hhoao/teampilot/member-hub/gstack-release"
    }
  ],
  "skillDeps": [],
  "pluginDeps": [],
  "mcpDeps": []
}
```

- [ ] **Step 2: Register in `team-hub/index.json`**

```json
{
  "teams": [
    { "slug": "gstack-req-dev" }
  ]
}
```

- [ ] **Step 3: Validate team JSON parses**

Confirm `DiscoverableTeam.fromJson` accepts the file (five roster slots; empty skillDeps; `teamMode` native; `cli` claude). Cross-check every `expertKey` exists under `member-hub/members/<slug>/` or will after Task 1.

- [ ] **Step 4: Commit** (only if user asked)

```bash
git add team-hub/teams/gstack-req-dev/team.json team-hub/index.json
git commit -m "$(cat <<'EOF'
feat(team-hub): add gstack-req-dev requirement delivery team

EOF
)"
```

---

### Task 3: Smoke-check indexes

- [ ] **Step 1: Confirm indexes**

- `member-hub/index.json` lists `gstack-developer`
- `team-hub/index.json` lists slug `gstack-req-dev`
- Every roster `expertKey` suffix matches a member-hub slug present in `member-hub/index.json`

- [ ] **Step 2: Done**

No Flutter analyze required (catalog-only). Optional: open Team Hub in app after pull to confirm card appears.
