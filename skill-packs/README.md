# Skill packs

Install-once skill bundles for TeamPilot.

```
skill-packs/
  index.json
  <slug>/pack.json
```

Built-in packs are also registered in-app (`SkillPackRegistry`). The `gstack` pack maps Garry Tan's [gstack](https://github.com/garrytan/gstack) sprint skills for Expert Hub personas under `member-hub/`.

Packs declare a step-graph `recipe` (`git.sync`, `skill.register-pack`, `fs.materialize`, `script.run`, …). See `docs/superpowers/specs/2026-07-24-skill-acquire-step-graph-design.md`.
