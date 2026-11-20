# Arena synthesis: ship-next

## Base
candidate-2 (`.audit/ship-next-design.md` in arena-ship-2). Cross-judge [Cross-judge ship-next designs](eef866df-cd02-4339-985c-b14dc536d966) totals 17 vs 14. Operator pick agrees.

## Why
Five flat fields on version 1, place enum that cannot encode a bad split pair, chord on the launch, concrete `session.view` reuse that fails closed, reuse before prompts.

## Disagreement with cross-judge on one criterion
Core loop: judge scored candidate-1 higher for pick→prompt→resolve→reuse. Operator keeps candidate-2's reuse-before-prompt. Experience First: a second press on a live agent must only focus.

## Grafts into base
1. From judge / candidate-1: pass `session_id` into the view request.
2. From judge / candidate-1: keep terminal-shell flavored blocks.
3. From judge / candidate-1: optional prompt `default` prefill.
4. From ship-next #1 / candidate-1: optional float `bounds` (parse-rejected on splits).

## Rejected from candidate-1
Version 2, root `binds`, reuse object with `if_missing`, applying `initial_input` on reuse hit, prompts before reuse.

## Verification of design
Synthesized file: `.audit/ship-next-design.md`. Covers all five ship-next items, names parse rejects, open order, reuse, binds, and tests. Ready for implementation.
