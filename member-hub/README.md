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
one of those experts installs the whole pack once via `acquire.kind = git-pack`.
