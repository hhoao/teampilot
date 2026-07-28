# Skill packs

Install-once skill bundles for TeamPilot.

```
skill-packs/
  index.json
  <slug>/pack.json
```

Built-in packs are also registered in-app (`SkillPackRegistry`). The `gstack` pack maps Garry Tan's [gstack](https://github.com/garrytan/gstack) sprint skills for Expert Hub personas under `member-hub/`.

## Author protocol

Packs declare an ordered Dockerfile-like `install[]` of single-key instruction
objects (`FROM`, `SKILLS`, `RUN`, `PATH`, `ENV`, …). There is no step-graph
`recipe` / `uses` surface.

Canonical shape (see `skill-packs/gstack/pack.json`):

```json
{
  "id": "garrytan/gstack",
  "name": "gstack",
  "install": [
    { "FROM": "garrytan/gstack@main" },
    { "SKILLS": "*" },
    { "RUN": "./setup", "optional": true },
    { "PATH": "bin" }
  ]
}
```

Full instruction set, path rules, and session PATH/ENV exports:
[`docs/superpowers/specs/2026-07-28-skill-pack-dockerfile-install-design.md`](../docs/superpowers/specs/2026-07-28-skill-pack-dockerfile-install-design.md).
