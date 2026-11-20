# Arena rubric: ship-next launch design

Artifact: `.audit/ship-next-design.md` describing schema + runtime for place, reuse, bind, prompt, initial_input.

## Criteria (score each 0–3)

1. **Compat.** Existing version-1 launches keep working without edits. Strict unknown-key behavior is addressed honestly (bump version, or allowlist new keys on v1 with defaults).
2. **Illegal states.** Place/reuse/bind/prompt/initial_input combos that cannot work are unrepresentable or rejected at parse with clear errors.
3. **Reuse correctness.** Identity, lookup, focus path, and stale-handle handling are specified without hand-wavy "find the pane".
4. **Core loop.** `open()` order keeps pick → (prompt) → resolve → place-or-reuse tight. No extra user steps for the default float case.
5. **Small surface.** Few new fields. Defaults match today's behavior. No parallel config formats or DSLs.
6. **Testable.** Named test cases cover parse rejects, defaults, reuse hit/miss, bind registration, and prompt cancel.
