# P3 — Render defects (result)

- **Date**: 2026-11-21 (matrix 2026-11-22)
- **Plan**: 2026-11-20 owner plan, P3-1…P3-4 (`P3 — Дефекты рендера. Независимо от P2.`)
- **Status**: working tree, pending owner approval. No commit, no push.
- **Acceptance criterion (plan)**: each defect gets a reproducible test, red
  before the fix, green after; behaviour on valid inputs unchanged
  (equivalence).

The plan text is the pre-registration. The three defects were reproduced on
the live runtime **before** any code change (2026-11-20, degraded mode), and
the pins were written and observed red before the fixes. This document
records the readings, the changes, the red/green evidence, the measured
surfaces, and the one place where the implementation interprets the plan.

---

## 1. What was read (with citations)

| Site | What it does |
|---|---|
| `src/QxFx0/Render/Dialogue.hs:620–631` | template contact path: greeting → `contactGreetingSurface`, otherwise the grounding line |
| `src/QxFx0/Render/Dialogue.hs:1763–1782` | `contactGreetingSurface` and the new `healthyContactSurface` (the healthy greeting text already existed here) |
| `src/QxFx0/Render/Dialogue.hs:2256–2257` | semantic-first `FT.ContactFrame` branch: `greeting <> ". Слышу, что сейчас нужна опора. …"` — **P3-2 source** |
| `src/QxFx0/Render/Dialogue.hs:1355–1368` | `microPlanPrefix` (`MvDefine` → «Сначала задам определение») |
| `src/QxFx0/Render/Dialogue.hs:1405–1411` | `MoveReflectMirror` fallback hold «Держу это как точку разбора.» |
| `src/QxFx0/Render/Dialogue.hs:355–365` | fragment gluing: style prefix + micro-plan preface + body |
| `src/QxFx0/Semantic/ResponsePlan.hs:629–647` | headline composition and the mode-aware self-proof branch |
| `src/QxFx0/Semantic/ResponsePlan.hs:702–705` | `basisSuffix` → `(основание: …)` — **P3-1 source** |
| `src/QxFx0/Core/TurnPipeline/Route/Render.hs:450–465` | artifact selection (semantic-first → assembly → template) and the **P3-3 guard** |
| `src/QxFx0/Semantic/Intent/Classifier.hs:328` + `Features.hs:211–217` | `IntentContact` is a greeting/courtesy mark only |
| `src/QxFx0/Semantic/Frame/Builder.hs:63–66`, `Frame/Types.hs:64–67` | `ContactFrame` carries only `cfGreeting`; it is the greeting/relationship frame |

The last two rows are why the `FT.ContactFrame` distress sentence is wrong
for the **whole** branch, not just for one input: a `ContactFrame` is built
only from the contact marks (greetings and small talk), so the distress
claim is false for every input that can reach it.

---

## 2. Reproductions (before the fix)

Live runtime, 2026-11-20, `QXFX0_RUNTIME_MODE=degraded`, fresh DB:

| Input | Family | Surface |
|---|---|---|
| `усталость` | `CMDefine` | `Определение: усталость требует восстановления (основание: усталость требует восстановления). Следующий ход: …` |
| `привет` | `CMContact` | `Привет. Слышу, что сейчас нужна опора. Давай упростим: выделим одну точку напряжения и выберем один короткий шаг на ближайшее время.` |
| `хм` | `CMReflect` | `Образно: Сначала задам определение Держу это как точку разбора.` |

Strict-mode control before the fix: `мне тяжело` and `расскажи о времени`
already showed the same gluing class (`Образно: Сначала задам определение …`),
but neither is a contentless input, so they are **not** part of P3-3 (see
§8).

---

## 3. Changes

### P3-1 — thesis ≡ basis

`src/QxFx0/Semantic/ResponsePlan.hs`

- `basisRepeatsThesis` compares the rendered thesis with the joined predicate
  refs after case/punctuation/whitespace normalisation (a trailing full stop
  cannot dodge the guard).
- **Known claim** (`ClaimKnown`, i.e. a definition): the turn abstains —
  `selfProofRefusal`, no thesis, asks for the frame criterion.
- **Hypothetical claim** (`ClaimHypothetical`, i.e. an uncovered-topic
  thesis): the thesis is kept, the circular basis is replaced by
  `selfProofSuffix` («основание совпадает с тезисом; нужен внешний
  критерий»), and the counterpoint/next move survive.

Interpretation note: the plan says «не рендерить, уходить в честный
отказ/уточнение рамки». For a known definition the turn now refuses, which
is the plan's literal case. For a hypothesis the thesis is already marked as
unproven, and a blanket refusal would delete the uncovered-topic doctrine
pinned by `testUncoveredClaimIsHypothesis` (`Test.Suite.ResponsePlan:37`) and
the legitimate counterpoint pinned by `testCounterpoint` (`:3`). The
mode-aware split keeps both behaviours honest: a self-proved **definition**
abstains; a self-proved **hypothesis** says so and asks for the criterion.

### P3-2 — rescue on a neutral input

`src/QxFx0/Render/Dialogue.hs`

- New `healthyContactSurface` (single source).
- `FT.ContactFrame greeting` → `greeting <> ". " <> healthyContactSurface`.
- `contactGreetingSurface` uses the same text for the `привет` branch.
- The distress lines at `:626`, `:635`, `:1941`, `:1943` are untouched: they
  belong to `AffectiveQ`/`ContactSignal`/`RepairSignal`, not to a greeting.

### P3-3 — fragment gluing

`src/QxFx0/Render/Dialogue.hs` + `src/QxFx0/Core/TurnPipeline/Route/Render.hs`

- `isContentlessUtterance`: tokens are empty or all in a narrow interjection
  lexicon (`хм`, `мм`, `эм`, `ээ`, `ага`, `угу`, `ох`, `ах`, `hmm`, `mm`,
  `mhm`, `uh`, `um`, `er`, `erm`). A single content token keeps the normal
  path, so «хм, а что такое свобода?» is unaffected.
- `contentlessSurface`: one coherent line, no invented topic.
- The guard runs after artifact selection (so it also wins over the
  semantic-first path), replaces `draRenderedText`/`draTemplateBodyText`,
  replaces any inherited `surface=` tag with `surface=contentless_filler`
  (exactly one surface tag survives), and stamps `contentless_guard=fired`
  in `draGenerationTrace`. The underlying fallback route is still visible in
  the remaining tags and in `trcSurfaceProvenance`; the guard is an overlay
  on that route, not a new provenance class.

### P3-4 — golden snapshots

- `spec/golden/render_snapshots_corpus.tsv` — 11 turns across 8 sessions:
  the three defect inputs, a definition → challenge → recover trajectory, a
  reflection, a distinction, a repair → small-talk trajectory, and a
  generative thesis.
- `scripts/eval/render_snapshots.py` — `--write`, `--check`, `--report`,
  `--self-test` (19 cases). Strict mode, one fresh DB per session, one
  process per turn, `QXFX0_BRAIN_KB_PATH` → missing file (substrate off, so
  the 44 MB gitignored `brain_kb.jsonl` is not a dependency).
- `spec/golden/render_snapshots_2026-11-21.tsv` — frozen surfaces, sha256
  `5be47deb22624a96f89f8c97fc489e191cd22ccd09c8eebcff5206bc4b1a054f`.
  Two independent `--write` runs (separate work directories, fresh DBs)
  produced byte-identical files before the freeze; `--check` on the final
  binary reports `11/11 match`.
- Registered in `docs/closure/PYTHON_SUPPLIER_ALLOWLIST.md` §1 (thirteen
  eval-only tools).

---

## 4. Red / green evidence

Pins were added before the fixes and run against the **pre-fix** binary:

| Pin | Suite | Red (pre-fix) |
|---|---|---|
| `tautological basis is not rendered as evidence` | `ResponsePlan` | `### Failure in: 0:ResponsePlan:41` |
| `contact frame greeting avoids distress framing` | `DialogueSemanticSelection` | `### Failure in: 0:DialogueSemanticSelection:45` |
| `contentless filler gets coherent reply` | `TurnPipelineProtocol` | `### Failure in: 0:TurnPipelineProtocol:72` |

Green after the fixes (targeted runs):

| Suite | Result |
|---|---|
| `ResponsePlan` (unit) | 42/42 |
| `TurnPipelineProtocol` (unit) | 231/231 |
| `Rescue` (unit) | 11/11 |
| `DialogueSemanticSelection` (fast) | 72/72 |
| `CoreBehavior` (fast) | 349/349 |

One honest miss during the work: the first P3-1 implementation refused
**every** mode when basis ≡ thesis. It regressed three pre-existing pins
(`ResponsePlan:3`, `:6`, `:37`) whose hypothetical fixtures reuse the thesis
as the basis. The final mode-aware version keeps them green **without
editing the fixtures**; the fixtures were not hiding the defect, they were
exercising a different mode.

The P3-1 pin was later extended with the `ClaimKnown` abstention case and
re-run green; the P3-3 pin was extended with a single-`surface=`-tag
assertion after the guard was made to replace (not duplicate) the fallback
surface tag. Both extensions were green on the final tree.

---

## 5. Measured surfaces after the fix

Strict mode, fresh DB, 2026-11-21:

| Input | Family | Surface |
|---|---|---|
| `привет` | `CMContact` | `Привет. Я на связи и готов к нормальному диалогу: можешь задать вопрос, выбрать тему или просто продолжить разговор.` |
| `хм` | `CMReflect` | `Я здесь. Скажи, о чём хочешь поговорить, — и я отвечу по существу.` |
| `усталость` | `CMDefine` | `Основание совпало с тезисом дословно, поэтому я не выдаю его как подтверждение. Уточни рамку: какой критерий должен подтвердить тезис?` |
| `что такое свобода?` | `CMDefine` | unchanged: `Тезис: свобода предполагает возможность выбора. Контрпункт: … Проверка: верно ли это?` |

Degraded mode shows the same three fixed surfaces plus the honest
«Часть проверок сейчас недоступна…» suffix.

---

## 6. Equivalence on valid inputs

The guard paths are narrow by construction:

- P3-1 fires only when `basisRepeatsThesis` **and** the claim is `ClaimKnown`;
  hypothetical plans keep the thesis and only lose the false evidence claim.
- P3-2 fires only on `FT.ContactFrame` / the greeting branch.
- P3-3 fires only on interjection-only tokens.

Spot checks (unchanged before/after): `здравствуйте`, `я устал`,
`мне тяжело`, `что такое свобода?`, `расскажи о времени`. The targeted
suites above (705 cases) are green, including the pre-existing greeting,
contact, rescue and response-plan pins. The full matrix is reported in §7.

---

## 7. Verification matrix

Matrix 2026-11-22, run on the final code tree (`HEAD b674a65` + 10
uncommitted paths: 7 modified, 3 new), start `2026-11-22T10:49:42Z`, end
`2026-11-22T16:09:31Z`. `git status --porcelain` is byte-identical
start→end; no code, spec or data file changed while it ran. The matrix ran
with this section still `TBD`; the only post-matrix change is this section
(docs-only), so the measured tree is the landing tree minus this text.

| Step | Cases | Errors | Failures |
|---|---|---|---|
| unit | 1 865 | 0 | 0 |
| fast | 1 967 | 0 | 0 |
| property | 245 | 0 | 0 |
| integration | 47 | 0 | 0 |
| main-http | 23 | 0 | 0 |
| slow-http | 23 | 0 | 0 |
| slow-lifecycle | 11 | 0 | 0 |
| main-runtime | 106 | 0 | 0 |
| slow-state | 50 | 0 | 0 |
| slow-runtime | 106 | 0 | 0 |

All ten steps exited 0: **4 443 cases, 0 errors, 0 failures**. The growth
over the 2026-11-19 matrix (4 437) is the six new cases: `ResponsePlan` +1
(unit), `TurnPipelineProtocol` +1 (unit, fast, property), and
`DialogueSemanticSelection` +2 (fast).

`scripts/check_architecture.sh` passed on the same tree, including rule [24]
(the new `render_snapshots.py --self-test`). `render_snapshots.py --check`
reports `11/11 match` against the frozen snapshots on the final binary.

Not re-run, same limitation as the previous matrices: the full single-process
`qxfx0-test` core slice (unsupported on 15 GB with the substrate active).
`main-http` and `main-runtime` were run per group; the core slice is covered
by `unit` + `fast` + `property` + `integration`.

---

## 8. Open items (not in this landing)

1. **General fragment gluing on non-empty inputs.** `расскажи о времени`
   and `мне тяжело` still render `Образно: Сначала задам определение
   Смысловая точка: …` — the same gluing class, but P3-3's named case is the
   contentless input. Fixing the reflection template would change valid
   inputs and needs its own pre-registration.
2. **Golden snapshot `reflection-time`** freezes the current glued surface.
   That is deliberate: the snapshot records current behaviour, not a quality
   verdict. When item 1 is fixed, `--write` will show exactly that one diff.
3. **`ResponsePlan` fixtures** (`:3`, `:6`, `:37`) use basis ≡ thesis for
   hypothetical plans. They stay green because the guard is mode-aware; a
   future change that makes them `ClaimKnown` will (correctly) abstain.
4. **`как жизнь?` keeps a default «Привет.» prefix** in strict mode: the
   `ContactFrame` greeting is `extractGreeting`'s fixed small-talk default
   (`Frame/Builder.hs:200–207`), so the surface reads «Привет. Я на связи…».
   The prefix is pre-existing (the old branch was `greeting <> ". Слышу, что
   сейчас нужна опора…"`); P3-2 removed only the false distress claim. A
   better small-talk opener is a separate change.
