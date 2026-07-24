# Member Hub registry

Public expert templates for TeamPilot live in this subdirectory of
[`hhoao/teampilot`](https://github.com/hhoao/teampilot).

```
member-hub/
  index.json                    # { "members": [ "<slug>", … ] }
  members/<slug>/member.json    # DiscoverableMember JSON
```

Catalog keys are stamped as `hhoao/teampilot/member-hub/<slug>`.

gstack sprint personas (`gstack-*`) depend on the `garrytan/gstack` **SkillPack**
(`skill-packs/gstack/pack.json` / in-app `SkillPackRegistry`). Installing any
one of those experts installs the whole pack once via the pack **install recipe** (sync → register skills → materialize `bin/` → optional `./setup`).

Optional `i18n.<lang>` overlays localize hub display fields (`name`,
`description`, `category`, `member.responsibilities` / `playbook`). Root fields
remain the default language; the app resolves with `DiscoverableMember.forLocale`
(e.g. UI locale `zh` → Chinese copy).
