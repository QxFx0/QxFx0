# QxFx0 Semantic Boundary Map

Date: 2026-04-24

This document fixes the boundary for semantic stabilization without expanding the architecture. QxFx0's current semantic path remains:

```text
raw input -> parseProposition -> collectAtoms -> runSemanticLogic -> runFamilyCascade -> render/finalize
```

`runSemanticLogic` is routing logic, not a proof engine. The goal is stable routing, focus extraction, guard classification, traceability, and non-destructive degradation under logical prose.

## Boundary Table

| Reasoning class | Status | Why |
|---|---|---|
| Term distinction: argument / explanation / axiom / theorem / ground | Supported | Maps naturally to `CMDefine` / `CMDistinguish` in the existing keyword/rule pipeline. |
| Surface syllogism, modus ponens, modus tollens recognition | Supported | Can route stably as define/clarify/ground without constructing a proof object. |
| Local negation: `не устал`, `не X, а Y` | Supported | Existing frame fields and local atom suppression are enough for first-order stabilization. |
| Focus extraction for logical prose | Supported | Solvable with stopwords, repeated-entity preference, and marker rules. |
| Simple quantifier traps with explicit `все / некоторые / every / some` | Degraded-but-safe | Can avoid repair and route to distinguish/clarify, but cannot prove scope relations. |
| Reductio in natural language | Degraded-but-safe | Can identify the task as explaining argument structure, not validate the proof. |
| Long philosophical sentence with one main distinction | Degraded-but-safe | Focus/family can be stabilized; deep parse is out of scope. |
| Nested negation / double negation / multi-pivot contrast | Degraded-but-safe | Local rules help, but exact scope remains fragile. |
| `forall x exists y` vs `exists y forall x` | Out-of-scope | Requires binder/scope representation absent from the current pipeline. |
| Arbitrary proof validity checking | Out-of-scope | No proof object or inference calculus exists in current architecture. |
| Countermodel generation | Out-of-scope | No model semantics or proof search. |
| Formal equivalence under renaming/scope transformation | Out-of-scope | No AST, alpha-equivalence, or normal form machinery. |
| Modal/deontic/temporal operator nesting | Out-of-scope | Keyword routing can discuss terms but cannot compute nested modal logic. |

## Stabilization Rule

The current architecture is considered stable for semantic load when it:

- Does not route ordinary logical prose to `CMRepair` without real distress/safety/policy-deny.
- Does not make logical connectives the main focus.
- Does not turn tool/policy degradation into emotional repair.
- Distinguishes define / distinguish / clarify / ground well enough for routing.
- Makes degradation trace-visible.
- Does not claim formal proof checking where no logical form exists.

## Non-Goals

Do not solve the corpus by adding:

- A new AST parser.
- An external dependency parser.
- A theorem prover.
- LLM-as-parser.
- A new reasoning engine.
- Golden snapshots of full rendered text.
