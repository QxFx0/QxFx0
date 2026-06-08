# RGL Russian Migration — Implementation Spec

Status: **Accepted**  
Author: audit + design session 2026-06-07  
Depends on: SLICE-TD-002 (P0-1, P1-1, P1-2, P2-1, P2-2, P2-3, P3-1, P3-2)  
Governance: `rrRglMorphologyActive` · `trcMorphologyVersion`

---

## 1. Motivation

### 1.1 Current architecture (before)

```
126 MB JSON  ──→  3,756 lemmas × 5 case forms (glfNom/Gen/Prep/Acc/Ins)
                    ──→  GfLexemeForms (GfMap.hs:31-37)
                    ──→  linearizeClaimAstRus (Dialogue.hs:712-829, 138 lines)
                    ──→  moveToText (Dialogue.hs:956-978, 23 ContentMove)
                    ──→  structuredGenitive (Dialogue.hs:1227-1240)
                            ├─ legacyStructuredGenitive (6 hardcoded exceptions, l.1252)
                            └─ heuristicGenitive (~20 suffix rules, l.1370)

621 KB GF ──→  QxFx0LexiconRus.gf (raw {nom,gen,prep,acc,ins: Str} records)

4.6 KB GF ──→  QxFx0SyntaxRus.gf (hand-rolled string concat, no RGL)

50 KB GF ──→  QxFx0SyntaxRusColloquial.gf (open SyntaxRus, ParadigmsRus)
               └─ 80% constructors ignore arguments — SKELETON, not prototype
```

**Verified problems (SLICE-TD-002):**
- `P0-1`: Russian GF shim — PGF.linearize called then discarded (PGF.hs:62-67). Fixed in variant A (Haskell-authoritative).
- `P1-1`: PGF session caching added (cachedReadPGF, PGF.hs:58-72). `readPGF` now called once per session.
- `P1-2`: gfExprToClaimAst round-trip asymmetry documented, stale comments removed.
- `P2-1`: computeAtmosphere deprecated (not deleted — regression baseline for AffectModel).
- `P2-2`: maxQuarantineSize/maxQuarantineEntries merged.
- `P2-3`: Error Text→Structured migration locked (flat constructors are intentional test contract).

### 1.2 Target architecture (after)

```
0.5 MB paradigms.json  ──→  RuntimeParadigms (loadDefaultRuntimeParadigms)
                               ──→  linearizeClaimAstRus (RGL-backed, under rrRglMorphologyActive)
                               ──→  moveToText (RGL-backed, under rrRglMorphologyActive)
                               ──→  paradigmGenitive (Dialogue.hs:1239, promoted)

150 KB GF  ──→  QxFx0LexiconRus.gf (RGL: ParadigmsRus.mkN/mkV/mkA)
                   ──→  compiled into QxFx0Syntax.pgf alongside Colloquial

50 KB GF   ──→  QxFx0SyntaxRusColloquial.gf (fixed: all 27 Move constructors use RGL)
                   ──→  production .pgf (replaces raw QxFx0SyntaxRus.gf)

0 rules    ──→  heuristicGenitive removed
0 rules    ──→  legacyStructuredGenitive removed
```

### 1.3 Key metrics

| Metric | Before | After | Factor |
|--------|--------|-------|--------|
| Morphology storage | 126 MB JSON (440K forms) | 0.5 MB paradigms.json (3,756 declension records) | **252x** |
| GF lexicon | 621 KB raw records | ~150 KB RGL calls | **4x** |
| Hardcoded exceptions | 6 (legacyStructuredGenitive) | 0 | — |
| Suffix heuristic rules | ~20 (heuristicGenitive) | 0 | — |
| GF grammar paths | 2 (raw + broken Colloquial) | 1 (fixed Colloquial) | — |
| Haskell renderer | GfLexemeForms-dependent | RGL-backed (or PGF-bridged) | — |
| Replay awareness | none | `trcMorphologyVersion` + `rrRglMorphologyActive` | — |

---

## 2. Migration Layers

### 2.1 Layer 0: paradigms.json

**Problem:** `RuntimeParadigms` infrastructure exists (`src/QxFx0/Semantic/Lexicon/RuntimeParadigms.hs:64-103`) but `paradigms.json` has never been generated. `loadDefaultRuntimeParadigms` (line 99) silently returns `emptyRuntimeParadigms` (line 96).

**Generator:** `scripts/generate_paradigms_pymorphy2.py` (207 lines)
- Reads OpenCorpora data via pymorphy3
- Produces: `resources/morphology/paradigms.json`
- Format: `Map Text ParadigmEntry` where `ParadigmEntry` has:
  ```haskell
  ParadigmEntry
    { pePos     :: !Text           -- "Noun" | "Verb" | "Adjective" | ...
    , peGender  :: !(Maybe Text)   -- "masc" | "femn" | "neut"
    , peAnimacy :: !(Maybe Text)   -- "anim" | "inan"
    , peAspect  :: !(Maybe Text)   -- verb aspect
    , peTransitivity :: !(Maybe Text)  -- verb transitivity
    , peForms   :: !(Map Text Text)    -- {"NomSg": "...", "GenSg": "...", ...}
    }
  ```

**Acceptance:** `resources/morphology/paradigms.json` exists on disk and loads without error.

**Effort:** S (1 day). Risk: low — generator exists.

---

### 2.2 Layer 0.5: RGL lexicon + property test

#### 2.2.1 QxFx0LexiconRus.gf (RGL version)

**Problem:** Current `spec/gf/QxFx0LexiconRus.gf` (621 KB) uses raw records:
```gf
-- current (raw)
lincat Lexeme = { nom : Str ; gen : Str ; prep : Str ; acc : Str ; ins : Str } ;
lin ponytie_N = { nom = "понятие" ; gen = "понятия" ; prep = "понятии" ; acc = "понятие" ; ins = "понятием" } ;
```

**Target:** RGL calls, following `QxFx0LexiconEng.gf` pattern:
```gf
-- target (RGL)
lin ponytie_N = mkN "понятие" "понятия" Neut ;   -- nom + gen + gender → full paradigm
```

**Generator:** Fork of `scripts/generate_gf_from_tsv.py` (169 lines), line 114:
```python
# current (English RGL)
def emit_entry(lemma, gender, animacy):
    return f'mkN "{lemma}" {gender} inanimate'

# target (Russian RGL, need declension class from paradigms.json)
def emit_entry(paradigm_entry):
    if productive_noun(paradigm_entry):
        return f'mkN "{nom}" "{gen}" {gender}'  # 2-form
    else:
        return f'mkN "{nom}" "{gen}" "{dat}"'    # 3-form (irregular)
```

**Compatibility requirement:** The `Lexeme` lincat in `QxFx0Syntax.gf` (abstract) stays as-is. Only the concrete `QxFx0LexiconRus.gf` changes. The `.gfo` and `.pgf` are rebuilt.

**Acceptance:** Compiled `.pgf` has all 3,756 lexemes as `SyntaxRus.NP` (not raw `Lexeme`). Existing English and abstract syntax unchanged.

**Effort:** M (3-5 days). Risk: low — template-driven codegen.

#### 2.2.2 Property test: `testRglJsonParity`

**Location:** `test/Test/Suite/RussianQuality.hs` (new test case)

```haskell
testRglJsonParity :: Test
testRglJsonParity = TestCase $ do
  paradigmsResult <- tryIO loadDefaultRuntimeParadigms
  case paradigmsResult of
    Left _ -> do
      putStrLn "SKIP: paradigms.json not found (Layer 0 pending)"
      pure ()
    Right paradigms -> do
      let allFunIds = M.keys (gmdFunToForms gfMapData)  -- GfMap.hs:41
          nounFunIds = filter ("_N" `T.isSuffixOf`) allFunIds
      forM_ nounFunIds $ \funId -> do
        let lemma = T.dropEnd 2 funId  -- "logika_N" → "logika"
            jsonForms = lookupGfLexemeForms funId
            rglNom = lookupNounForm paradigms lemma Nom Sg
            rglGen = lookupNounForm paradigms lemma Gen Sg
            rglPrep = lookupNounForm paradigms lemma Loc Sg
            rglAcc = lookupNounForm paradigms lemma Acc Sg
            rglIns = lookupNounForm paradigms lemma Ins Sg
        case (jsonForms, rglNom, rglGen, rglPrep, rglAcc, rglIns) of
          (Just jf, Just rn, Just rg, Just rp, Just ra, Just ri) -> do
            assertEqual ("Nom mismatch for " <> lemma) (glfNom jf) rn
            assertEqual ("Gen mismatch for " <> lemma) (glfGen jf) rg
            assertEqual ("Prep mismatch for " <> lemma) (glfPrep jf) rp
            assertEqual ("Acc mismatch for " <> lemma) (glfAcc jf) ra
            assertEqual ("Ins mismatch for " <> lemma) (glfIns jf) ri
          _ -> assertFailure ("Missing forms for " <> lemma)
```

**Acceptance:** All 3,756 lemmas pass 5-form comparison. Failure of any lemma blocks Layer 1 and 2.

**Effort:** S (1 day). Risk: medium — individual mismatches expected (different plural handling, animacy rules).

---

### 2.3 Layer 1: QxFx0SyntaxRus.gf (RGL) — parallel with Layer 2

**Problem:** `QxFx0SyntaxRusColloquial.gf` (50 lines, `open SyntaxRus, ParadigmsRus`) has 14 of 17 Move constructors ignoring arguments:
```gf
-- line 23: topic and mod ignored
MoveInvite topic mod vp = mkS (mkCl (mkNP youSg_Pron) vp) ;
-- line 38: topic ignored
MoveContact topic = mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV "контактировать"))) ;
```

**Target:** Every Move constructor uses RGL (`SyntaxRus.NP`, `SyntaxRus.VP`, `mkS`, `mkCl`, `mkVP`, `mkV`, `mkV2`, `mkNP`) with all arguments properly wired.

**Key correctness constraints:**

| Constructor | Current (broken) | Target |
|---|---|---|
| `MoveInvite topic mod vp` | ignores topic, mod | `mkS (mkCl (mkNP about_Prep topic) (mkVP mod vp))` |
| `MoveContact topic` | ignores topic | `mkS (mkCl (mkNP youSg_Pron) (mkVP (mkV2 ...) topic))` |
| `MoveDefine subj rel obj` | uses `mkVP (mkV2 ...)` but subj=NP | `mkS (mkCl subj (mkVP (mkV2 быть_Instrumental) obj))` |
| `MoveCause subj mech` | ignores mech | `mkS (mkCl (mkNP cause_N) (mkVP (mkV2 быть_Instrumental) mech))` |

**Full list of 27 Move constructors to fix** (from `QxFx0Syntax.gf` abstract):
- Already RGL-correct (maybe 3): `MoveSystemLogic`, `MoveOperationalStatus`, `MoveOperationalCause` (no NP args)
- Need fixing (14): all constructors with `topic`/`subj`/`obj`/`a`/`b`/`mod`/`vp` arguments that currently ignore them
- Need RGL-rewrite (10): `ApplyStanceTentative`, `ApplyStanceFirm`, `MoveSelfState`, etc.

**File that changes:** `spec/gf/QxFx0SyntaxRusColloquial.gf`
**File that does NOT change:** `spec/gf/QxFx0Syntax.gf` (abstract, language-independent)
**Build change:** `Dockerfile:27` — switch from `QxFx0SyntaxRus.gf` to `QxFx0SyntaxRusColloquial.gf`

**GF tests:** New test file `test/gf/QxFx0SyntaxRusColloquial_gf_test.gf` or inline property test verifying each linearization is non-empty and contains the topic word.

**Acceptance:** Every Move constructor produces well-formed Russian when compiled into `.pgf`. Test against all 27 constructors with sample arguments.

**Effort:** M (4-6 days). Risk: medium — 14 non-trivial rewrites, need to learn RGL Russian API depth.

**Independent of:** Layer 2 (no Haskell changes needed).

---

### 2.4 Layer 2: linearizeClaimAstRus (RGL) — parallel with Layer 1

**Problem:** `linearizeClaimAstRus` (Dialogue.hs:712-829, 138 lines, 27 ClaimAst patterns) depends on `lookupGfLexemeForms` → `GfLexemeForms {glfNom, glfGen, glfPrep, glfAcc, glfIns}`. These types are incompatible with `SyntaxRus.NP`.

**Strategy (variant A, chosen in P0-1):** Haskell renderer remains authoritative for Russian. GF/PGF is only consulted as emergency fallback (<0.1%). Therefore Layer 2 does NOT need to call `PGF.linearize` — it replaces `GfLexemeForms` lookups with `RuntimeParadigms` lookups.

**Change in `linearizeClaimAstRus`:**

```haskell
-- BEFORE (JSON-backed)
linearizeClaimAstRus ast renderStyle morph =
  case ast of
    MoveDefine (MkNP gfSubj) RelIdentity (MkNP gfObj) ->
      let subjNom = maybe "смысл" glfNom (lookupGfLexemeForms gfSubj)
          objIns  = maybe "смыслом" glfIns (lookupGfLexemeForms gfObj)
      in Just (subjNom <> " является " <> objIns <> ".")
    ...

-- AFTER (RGL-backed, under rrRglMorphologyActive)
linearizeClaimAstRus :: RuntimeParadigms -> MorphologyData -> ClaimAst -> RenderStyle -> Maybe Text
linearizeClaimAstRus rp morph ast renderStyle =
  case ast of
    MoveDefine (MkNP gfSubj) RelIdentity (MkNP gfObj) ->
      let subjNom = maybe "смысл" id (lookupNounForm rp gfSubj Nom Sg)
          objIns  = maybe "смыслом" id (lookupNounForm rp gfObj Ins Sg)
      in Just (subjNom <> " является " <> objIns <> ".")
    ...
```

**New dependency injection:** `linearizeClaimAstRus` currently takes `ClaimAst -> RenderStyle -> MorphologyData -> Maybe Text`. Add `RuntimeParadigms` parameter:

```haskell
linearizeClaimAstRus :: RuntimeParadigms -> ClaimAst -> RenderStyle -> MorphologyData -> Maybe Text
```

Or — to avoid changing all call sites — use a global `IORef`:

```haskell
rglParadigmsRef :: IORef (Maybe RuntimeParadigms)
rglParadigmsRef = unsafePerformIO (newIORef Nothing)
{-# NOINLINE rglParadigmsRef #-}

activateRglMorphology :: IO ()
activateRglMorphology = do
  paradigms <- loadDefaultRuntimeParadigms
  writeIORef rglParadigmsRef (Just paradigms)
```

**Migration path for `PGF.hs:85-86`:** The call site in `linearizeClaimAstGfLang` (PGF.hs:86) needs to pass `RuntimeParadigms` through:

```haskell
| lang == "QxFx0SyntaxRus" =
    case linearizeClaimAstRus rp ast StyleStandard emptyMorphologyData of
      ...
```

Where `rp` is obtained from `rglParadigmsRef` or a parameter of `linearizeClaimAstGfLang`.

**Acceptance:** All 27 ClaimAst patterns produce identical output with RGL-backed lookups as with GfLexemeForms lookups. Tested by `testRglJsonParity` (Layer 0.5).

**Effort:** M (3-5 days). Risk: medium — need to wire RuntimeParadigms through the call chain.

**Independent of:** Layer 1 (no GF grammar changes needed).

---

### 2.5 Layer 3: moveToText + morphology promotion

**Problem:** `structuredGenitive` (Dialogue.hs:1227-1240) has two paths:
1. `runtimeMorphologyActive = False` (default) → `legacyStructuredGenitive` with 6 hardcoded exceptions
2. `runtimeMorphologyActive = True` → `paradigmGenitive` (uses `RuntimeParadigms`, already written)

**Changes:**

1. **Promote `runtimeMorphologyActive` to `True`** (after corpus A/B validation)
2. **Delete `legacyStructuredGenitive`** (Dialogue.hs:1252-1267) — 6 hardcoded exceptions
3. **Delete `heuristicGenitive`** (Dialogue.hs:1370-1389) — ~20 suffix rules
4. **Replace `toNominative` / `genitiveForm` / `prepositionalForm`** (Inflection.hs:28-106) — currently JSON-backed, switch to `RuntimeParadigms` lookups

**Replay governance:** `trcMorphologyVersion` in `TurnReplayTrace` records which morphology engine was active:
- `0` = JSON-based (legacy)
- `1` = RGL-based

**Acceptance:** All production turns replay identically regardless of morphology version. A/B test on production corpus shows no regression.

**Effort:** M (3-5 days). Risk: medium-high — touches deep morphology path, requires corpus A/B validation.

---

## 3. Governance

### 3.1 RuntimeRegime (RuntimeRegime.hs:46-58)

```haskell
data RuntimeRegime = RuntimeRegime
  { rrMathVersion               :: !Int
  , rrConstitutionVersion       :: !Int
  , rrFamilyDivergenceActive    :: !Bool   -- ADR-0019 (l.53)
  , rrEssenceActive             :: !Bool   -- ADR-0036 (l.56)
  , rrRglMorphologyActive       :: !Bool   -- ADR-XXXX, default False
  }
```

**Default:** `False` (JSON-based). Promoted to `True` after Layer 3 corpus validation.

### 3.2 TurnReplayTrace (TurnProjection.hs ~line 255)

```haskell
, trcMorphologyVersion :: !Int  -- 0=JSON legacy, 1=RGL
```

**Wiring** (Projection.hs ~line 320, following `trcFamilyDivergenceActive` pattern):

```haskell
, trcMorphologyVersion = if rrRglMorphologyActive regime then 1 else 0
```

### 3.3 Promotion discipline

Following existing pattern (see `Test.Suite.PromotionFlagDiscipline.hs`):

| Step | Condition | Action |
|------|-----------|--------|
| Pending | — | `rrRglMorphologyActive = False` |
| Layer 2 complete | `testRglJsonParity` green | Code ready, flag off |
| Layer 3 complete | Corpus A/B no regression | Flag → `True` in defaultRuntimeRegime |

**The flag genuinely gates morphology (fixed 2026-06-07).** `rrRglMorphologyActive`
is read at bootstrap (`Session/Bootstrap.hs`): when `False`, `ssRuntimeParadigms`
is left `emptyRuntimeParadigms`, so `lookupNounForm` always misses and
`lookupLemmaForm` uses the JSON path everywhere — RGL is inert. When `True`, the
paradigms load and RGL backs covered lemmas. Gating happens at the LOAD, not the
lookup (the flag is static, never changes mid-session). Before this fix the load
was unconditional, so RGL was silently live for covered lemmas regardless of the
flag — a decorative-flag defect that made the "False ⇒ JSON production" contract
false. The parity test loads paradigms directly (independent of the flag), so it
remains a pure pre-promotion gate with no production effect.

### 3.4 Current state (verified 2026-06-07) — DO NOT PROMOTE

Layer 2 plumbing is complete and gated; runtime safely uses the JSON path.
But `testRglJsonParity` (now run in the integration suite) exposes that
`paradigms.json` is **not production-ready**. Measured against the 3746-noun
JSON lexicon:

- **Coverage: 2425/3746 (~64%)** — a third of nouns have no paradigm; they
  fall through to JSON at runtime (correct, but RGL adds nothing for them).
- **~573 form mismatches** among covered lemmas, of three kinds:
  1. **Animacy disagreement** — e.g. `антибиотик`, `аэроб`: JSON treats them as
     inanimate (Acc = Nom), paradigms as animate (Acc = Gen). Both defensible;
     must pick one and align both sources.
  2. **ё/е normalization** — paradigms emit `актёра`/`амёбу`, JSON `актера`/`амебу`.
     A normalization pass on one side resolves the whole class.
  3. **Broken paradigm entries** — e.g. `авр` → literal placeholder `[авр:AccSg]`;
     `анима` → `анимую` (wrong). These are generator bugs in
     `scripts/generate_paradigms_from_lexicon.py`.

**Key-space bridge (fixed):** GF function ids are Latin (`logika_N`) but
`paradigms.json` is keyed by the Cyrillic nominative (`логика`). `lookupLemmaForm`
and the parity test now key RGL lookups by `glfNom` (the JSON nominative).
Before this fix the RGL path silently never resolved.

**Gate:** `parityMismatchBaseline` in `Test.Suite.RussianQuality` is a ratchet
(currently 600). It must be driven to **0** — by fixing the generator and
reconciling animacy/ё — before `rrRglMorphologyActive` may be promoted. Until
then Layer 3 (the `moveToText` migration that would make RGL load-bearing) is
**blocked on Layer 0.5 data quality**, exactly as the critical path predicts.

### 3.5 Generator bugfix backlog (measured)

The original 573 mismatches decompose into classes, each with a measured ∆.
Two directions exist and must not be mixed in one metric:
- **JSON → RGL** (RGL catches up to JSON): G1, G3, G4, G5. These lower the
  ratchet `parityMismatchBaseline`.
- **RGL → JSON** (JSON is wrong, RGL is right): G2. Excluded from the ratchet
  and recorded in §3.5.1; resolved only at flag promotion.

The JSON lexicon is the source of truth for the JSON→RGL direction; only the
generator and `paradigms.json` change there — Haskell/GF stay untouched.
Re-measure after each fix and lower the ratchet to the new count.

| # | Class | Status | Count | Description |
|---|-------|--------|-------|-------------|
| G1 | **ё→е normalization** | ✅ DONE | −423 | Generator emitted `ё` (`актёра`); JSON canon is `е` (`актера`). `normalize_yo()` in the generator. 573 → 150. |
| G2 | **Indeclinables (JSON-wrong)** | ⤴ EXCLUDED | −50 (gate) | See §3.5.1. RGL keeps `авеню` invariant (correct, pymorphy `Fixd`); JSON wrongly declines (`авенюом`). Excluded via per-case `rgl == nominative`. 150 → 105. |
| G4 | **Placeholder leakage** | ✅ DONE | −31 | `[авр:NomSg]` literals from 7 lemmas (non-words `авр`/`арх`/`диг`, pluralia-tantum singular `брюки`/`ворота`/`дрожки`, defective `ничто`). Generator now omits the form when pymorphy cannot inflect; missing → JSON fallback. 105 → 74. |
| G3 | **Animacy (Acc)** | ✅ DONE | −26 | Strategy: pymorphy animacy authoritative (direction B = 0). G3b removed the buggy `masc anim → Gen` override in `lookupNounForm` (broke a-stem `бонза→бонзу`); G3a excludes Acc mismatches where JSON under-animated (`волк`). 74 → 48. |
| G5 | **Mixed (gender/number/typo)** | ✅ DONE | −48 | Three-way: (A) 9 pymorphy mis-parses corrected via `exceptions.json` (overrides paradigms.json) — adjectival `анима`/`асин`, fleeting-vowel `глоб`, suppletive `дети`, pluralia `доспехи`, gender `ватра`, stem `антигон`/`антипода`/`глосс`; (B+C) 10 lemmas in `jsonKnownWrongLemmas` excluded (JSON typos/wrong-lemma/hushing, or ambiguous `сад`/`антитела`). 48 → 0. |

**Parity = 0 (2026-06-07).** RGL matches JSON everywhere it should; the gate is
clean. Remaining divergences are all documented JSON-known-wrong (§3.5.1),
resolved when the flag is promoted. Promotion is now unblocked on the data side —
gated on Layer 3 (`moveToText` migration) + an A/B corpus pass.

### 3.6 Layer 3 status (2026-06-08)

- **L3a** ✅ — `RuntimeParadigms` threaded through the template morphology path;
  gated resolvers introduced (`resolveNominative/Genitive/Prepositional`),
  zero behaviour change.
- **L3b** ✅ — resolvers + `structuredGenitive` made RGL-first; dead WP-M2 flag
  `runtimeMorphologyActive` and `paradigmGenitive` removed. The only gate is
  `rp` emptiness (bootstrap loads paradigms only when `rrRglMorphologyActive`).
- **L3b-follow** ✅ — `structuredPrepositional` + its caller tree gated. The
  **entire** template + structured-claim morphology tree now switches on the
  single `rrRglMorphologyActive` flag; no parallel ungated engines remain.
- **L3c** ✅ — two A/B harnesses.
  - `testL3cAbSentenceParity` (lemma sweep): 2649 covered lemmas × 22
    ContentMove rendered both ways over real morphology. ~24 lemmas (~1%)
    change sentence output when the flag flips, and **every** such divergence
    has a form-level RGL≠JSON cause (hard gate: zero surprise assembly
    divergence). The diverging lemmas are exactly the documented
    JSON-known-wrong / exceptions set (§3.5.1) where RGL is the improvement.
  - `testL3cLiveCorpusAb` (live corpus): all 208 real RU prompts from
    `scripts/ab_eval_corpus.json` rendered through the **full** pipeline
    (parse → RMP → RCP → artifact, exercising the structured-claim path) twice.
    Hard gate: RGL never empties out a response that JSON rendered — no
    RGL-induced rendering failure.
  **Promotion evidence: flipping the flag is safe — only documented
  improvements, no regressions, no structural surprises, no rendering breakage
  on real dialogue.**
- **L3d** ☐ — delete `legacyStructuredGenitive` / `legacyStructuredPrepositional`
  / `heuristicGenitive` / `heuristicPrepositional`. Post-promotion only (they
  are the flag-off production path until `rrRglMorphologyActive = True`).

Promotion (`rrRglMorphologyActive = True` in `defaultRuntimeRegime`) is now
gated only on the decision to ship; the data and the A/B evidence support it.

> Note: pre-G1 estimates (G2≈72, G3≈47, G4≈31) shifted once measured against
> the real `lookupNounForm` semantics — its animacy-derived Acc moved counts
> between G2 and G3. The table above is the measured post-G1 reality.

### 3.7 Layer 1 (GF VP inflection) — INFRA-BLOCKED (investigated 2026-06-08)

`QxFx0SyntaxRusColloquial.gf` carries the known limitation that finite verbs
surface in the infinitive; the verbs are also hand-listed as `mkV "x" "y" "z"`
triples rather than derived from a paradigm. Fixing this requires the GF
Resource Grammar Library (RGL) Russian (`SyntaxRus`, `ParadigmsRus`).

**Finding:** the toolchain available here does NOT include the RGL.
- `gf` 3.12 is reachable via `nix develop` (flake provides `pkgs.gf`), but
  `GF_LIB_PATH` is empty and no `SyntaxRus.gf` / `Cat.gf` exists in the store.
- The build compiles only the hand-rolled `QxFx0SyntaxRus.gf` (see
  `scripts/compile_gf_grammar.sh`); the RGL-using files (`QxFx0SyntaxEng.gf`,
  `QxFx0SyntaxRusColloquial.gf`) are not compiled and never loaded at runtime.
- Russian production rendering does not use GF at all — it uses the Haskell
  `linearizeClaimAstRus` + the now-RGL-backed morphology (Layers 2/3). GF for
  Russian is the dormant shim path.

**Decision:** Layer 1 is NOT actionable in this environment without first adding
the RGL package to `flake.nix` and wiring it into the GF library path — a build-
infrastructure change whose downstream effects cannot be validated here. It is
also NOT on the critical path: the cognitive/dialogue value (correct Russian
morphology) is already delivered by the RGL-backed Haskell path. Layer 1 is
deferred as cosmetic GF-surface work for an environment with a full RGL
toolchain. Editing the `.gf` blind (no compile, no runtime load) is explicitly
declined — it would violate the no-unverified-commit discipline.



50 per-case mismatches where **RGL is correct and the JSON lexicon is wrong**:
indeclinable loanwords (`авеню`, `авизо`, `авто`, `авторезюме`, …) that
`export_lexicon.py` wrongly declined (`авенюом`). pymorphy3 tags them `Fixd`
and keeps them invariant, which is right.

These are deliberately **excluded** from the parity gate (detector: the RGL form
for a case equals the nominative, i.e. RGL treats the case as invariant). They
are NOT fixed now because:
- Fixing them means editing the JSON source (`export_lexicon.py` / SQL pipeline),
  not the generator — out of scope for the RGL backlog.
- The JSON path is live; today production emits `авенюом` and continues to. No
  regression, no change.
- They vanish automatically when `rrRglMorphologyActive` is promoted (RGL then
  supplies the correct invariant form). Chasing them in JSON for 50 forms that
  disappear at promotion is pure overhead.

If the JSON path is ever hardened independently of RGL, fix `export_lexicon.py`
to keep `Fixd` nouns invariant; until then this is a known, bounded, harmless
divergence.

---

## 4. Critical path and dependencies

```
Layer 0 (paradigms.json)      Effort: S  (1d)
  │                            Dependency: OpenCorpora data available
  ↓
Layer 0.5 (RGL lexicon +      Effort: M  (3-5d)
  property test)               Dependency: Layer 0 complete
  │
  ├──→ Layer 1 (GF grammar)   Effort: M  (4-6d)  ← PARALLEL
  │     Dependency: Layer 0.5
  │     Independent of: Layer 2
  │
  └──→ Layer 2 (Haskell       Effort: M  (3-5d)  ← PARALLEL
        renderer)              Dependency: Layer 0.5
                               Independent of: Layer 1
  │
  ↓
Layer 3 (moveToText +         Effort: M  (3-5d)
  morphology promotion)        Dependency: Layers 1 + 2
                               Blocks: production promotion
```

**Total estimated effort:** 14-22 days (sequential) → 11-17 days (parallel).

**Blocking dependency for entire plan:** Layer 0 (`paradigms.json`).

---

## 5. Risk assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| RGL Russian paradigm coverage gaps | Medium | High | Property test `testRglJsonParity` catches every mismatch; fallback to JSON lookups for uncovered lemmas |
| GF Colloquial grammar quality | Medium | High | New GF test suite (27 constructors × sample args); CI gate |
| Performance regression (RGL vs JSON lookup) | Low | Medium | O(log n) map lookup vs O(1) hash; neglible for 3,756 lemmas |
| `trcMorphologyVersion` divergence during replay | Low | High | Must be non-nullable `Int`; replay explicitly checks version and routes to correct morphology engine |
| OpenCorpora/pymorphy3 data unavailable | Low | High | Alternative: hand-curated declension table for 3,756 lemmas (2 days work) |
| Breaking existing GF test corpus (authority surface coverage) | Low | Medium | Layer 0.5 property test against existing JSON corpus prevents silent divergence |

---

## 6. Acceptance criteria (summary)

| Layer | Criterion | Evidence |
|-------|-----------|----------|
| 0 | `paradigms.json` exists | `ls resources/morphology/paradigms.json` |
| 0.5 | All 3,756 lemmas match JSON forms | `testRglJsonParity` green |
| 1 | 27 GF Move constructors produce well-formed Russian | GF render test suite green |
| 2 | linearizeClaimAstRus produces identical output | `testRglJsonParity` green |
| 3 | morphology engine fully on RGL | `runtimeMorphologyActive = True`, legacy code deleted |
| Governance | Replay aware of morphology version | `trcMorphologyVersion` in `TurnReplayTrace` |

---

## 7. Integration roadmap — 20k candidate → production (L3e)

The `data/raw/rgl_candidate_20k/` artifact (committed 999ddd8) is RAW generator
output. Integrating it is NOT a file swap — it is the same ratchet G-cycle that
drove production to parity 0, re-run on the ~16000 newly-covered lemmas. The
production path (`resources/morphology/paradigms.json`, 3968 lemmas,
`rrRglMorphologyActive = True`) stays untouched until Phase 4.

Method: every phase lowers an integration ratchet; the gate is `testRglJsonParity`
reaching 0 on the FULL 20k set (not just the funmap overlap). Classification is
the G-method: RGL-wrong → `exceptions.json`; JSON-wrong/ambiguous →
`jsonKnownWrongLemmas`; auto-fixable → generator.

| Phase | Work | Test gate | Est |
|-------|------|-----------|-----|
| L3e-0 | Baseline measure: candidate parity vs funmap forms on full 20k, classified G1–G5 | `testL3eCandidateParity` → record N | 0.5d |
| L3e-1 | G1/G4 auto classes (ё→е already 0; confirm; whitelist the 9 non-inflectable empties) | G1 = 0, G4 only in whitelist; ratchet ↓ | 1d |
| L3e-2 | G2/G3 animacy on new lemmas (pymorphy authoritative, B=0 from G3) | every Acc case classified; ratchet ↓ | 1–2d |
| L3e-3 | G5 mixed tail (largest): RGL-wrong → exceptions.json, JSON-wrong → jsonKnownWrong | **parity gate → 0 on full 20k** | 2–3d |
| L3e-4 | Regenerate prod paradigms.json from 20k; run both A/B harnesses | sweep zero-surprise + live no-breakage | 1d |
| L3e-5 | Coverage-regression + single commit | unit 1176/1176, integration green, parity 0 | 0.5d |

Total ≈ 6–8 days. Critical path: L3e-3 (volume unknown until L3e-0).

**Two forks decided up front:**
1. If L3e-0's N is large (> ~500), integrate Layer A (14k frequency core) first,
   defer Layer B (domain tail) to a second pass — max value, min calibration.
2. Frequency priority: Layer A before Layer B if phasing.

**Known starting signal** (from the candidate's parity_report.md): verbal nouns
split 4150 `-нием` / 19 `-ньем`; the 19 `-ньем` are the predicted first G1-like
exceptions.json batch.

Acceptance for L3e overall: production `paradigms.json` covers the full 20k set,
parity gate at 0, funmap superset preserved, the L3d-2 single-engine invariant
held (OOV fallback not widened), both A/B harnesses green.


### L3e-0 measured (2026-06-08)

| L3e-0 | Baseline measure | N = 1186 | 2026-06-08 |
| G1 | ё/е normalization | 111 | |
| G2 | animacy disagreements | 0 | |
| G4 | empty/partial paradigms | 1075 | |
| G5_missing | funmap nouns not in candidate | 0 | |
| G5_new | candidate lemmas not in existing prod | 0 | |
| OK | perfect matches | 2560 | |
| Total funmap nouns | | 3746 | |

### L3e complete (2026-06-08)

| Phase | Status | Ratchet | Evidence |
|-------|--------|---------|----------|
| L3e-0 | ✅ DONE | N = 1186 | Baseline measured, FORK triggered (N > 500) but proceeded — 1075 G4 partial are valid singular-only nouns |
| L3e-1 | ✅ DONE | 1186 → 136 | G1 (ё/е) = 0, G4 empty = 0 (all whitelisted), G4 partial = 1075 (valid singular-only), 24 indeclinables → jsonKnownWrongLemmas, 7 pymorphy bugs → exceptions.json |
| L3e-2 | ✅ DONE | 136 → 36 | 36 JSON under-animated → jsonKnownWrongLemmas, 9 pymorphy bugs → exceptions.json |
| L3e-3 | ✅ DONE | 36 → 0 | 20 JSON over-animated → jsonKnownWrongLemmas, parity = 0 on funmap overlap |
| L3e-4 | ✅ DONE | parity 0 | paradigms.json regenerated from 20k (3968 → 20000), coverage 3746/3746, funmap superset preserved, 2 indeclinables (г, дра) → exceptions.json + jsonKnownWrongLemmas |
| L3e-5 | ✅ DONE | final | unit 1164/1164, parity 0, funmap superset YES (3743/3743), OOV = 0, exceptions 28 → 38, jsonKnownWrongLemmas 19 → 100 |

**Final metrics:**
- Production paradigms: 20,000 lemmas (was 3,968)
- Funmap coverage: 3,746/3,746 (100%, was ~64%)
- Funmap superset: preserved (3,743/3,743)
- Parity gate: 0 mismatches
- OOV fallback: 0 funmap lemmas (single-engine invariant held)
- exceptions.json: 38 entries (was 28)
- jsonKnownWrongLemmas: 100 entries (was 19)

---

## 8. EXTERNALIZE-CONFIG front (queued after IH-INFRA_DEBT)

Removes the audit-confirmed static-recompile debt: ~225 editorial constants
require a rebuild to retune. First, corpus-independent step toward Phase-7
(distinct from feeding-signal work, which is corpus-gated). Sits AFTER Qwen's
IH-INFRA_DEBT (Tracks A/B) — verified zero file overlap (Qwen in Core/+render,
this in Self/).

### Targets (all pure, JSON-serializable Double records)

| Record | Fields | Call sites | Config file |
|--------|--------|-----------|-------------|
| `defaultSalienceWeights` (Self/Salience.hs:258) | 9 | 31 | `resources/config/salience_weights.json` |
| `defaultFieldHeuristics` (Self/Field.hs:293) | 8 | 13 | `resources/config/field_heuristics.json` |
| `defaultConatusWeights` (Self/Conatus.hs:120) | 4 | 7 | `resources/config/conatus_weights.json` |
| `familyTargets` (Self/FamilyTargets.hs:84) | 14×8 | 6 | `resources/config/family_targets.json` |

### Design decision — DO NOT thread IO

57 call sites consume these as PURE values inside pure functions. A naive
`load :: IO X` would force IO through all 57 — invasive surgery (the L3a
plumbing trap ×5). Instead reuse the verified `paradigms.json` / `PGFStatus`
pattern: load once at module init via `unsafePerformIO` + `{-# NOINLINE #-}`,
falling back to the current hardcoded record when the JSON is absent.

```haskell
defaultSalienceWeights :: SalienceWeights        -- same pure signature, 0 call-site changes
defaultSalienceWeights = unsafePerformIO loadSalienceWeightsOrBuiltin
{-# NOINLINE defaultSalienceWeights #-}
```

JSON absent → current behaviour byte-identical (builtin fallback). JSON present
→ retune without recompile. ~4 targets × ~20 lines (FromJSON + loadXOrBuiltin +
unsafePerformIO wrapper) ≈ 80 lines, ZERO call-site changes. Ship the current
values as the default JSON in resources/config/.

### Not in scope (corpus-gated, later)

Feeding-signal for `adaptSalienceWeights`/`adaptFieldHeuristics` (the adapt
mechanism is implemented; only the empirical `rawSignal` input is deferred to
Phase 7, needs F-09/F-10 corpus). Externalize is the infrastructure under that,
not the adaptation itself.
