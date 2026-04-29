# QxFx0 Semantic Stabilization Research Pack

Date: 2026-04-24

Purpose: provide one browser-friendly file with the key research questions, observed failures, and code excerpts needed to study QxFx0 semantic stability without uploading the full repository.

Hard constraint for all research: do not expand architecture. Do not propose a new parser subsystem, external reasoning engine, or broad rewrite. Work inside the existing path:

```text
raw input -> parseProposition -> collectAtoms -> runSemanticLogic -> runFamilyCascade -> render/finalize
```

The goal is stabilization: small rules, better gates, better tests, better diagnostics.

## How To Use This File In Browser Research

Paste this whole file into a research-level model and start with the master prompt below. The model should treat the code excerpts as the source of truth and should not invent new project structure.

```text
You are doing a stabilization research pass for QxFx0, a Haskell semantic-routing system.

Your task is not to redesign it. Your task is to find the smallest robust changes that make the existing architecture stable under meaningful logical/Russian inputs.

Hard constraints:
- Do not propose a new parser subsystem.
- Do not propose an external dependency parser, theorem prover, LLM-as-parser, or new reasoning engine.
- Do not propose a broad architecture rewrite.
- Keep the current pipeline: raw input -> parseProposition -> collectAtoms -> runSemanticLogic -> runFamilyCascade -> render/finalize.
- Prefer local Haskell changes, better invariants, better tests, and better diagnostics.
- If a problem cannot be solved inside the current architecture, explicitly mark it as "out of scope for current architecture" instead of proposing architectural growth.

Use the code excerpts and observed failures in this file. Produce:
1. Root-cause diagnosis.
2. Minimal stabilization plan split into P0/P1/P2.
3. Exact invariants/tests that prove the fix.
4. Risks and false positives.
5. What not to change.
6. A final "architecture expansion risk" score for each recommendation.
```

Expected answer style:

```text
Finding:
- What breaks.
- Why it breaks in the shown code.
- Minimal local fix.
- Test/invariant.
- Architecture expansion risk: Low/Medium/High.
- If High, reject or replace with a smaller solution.
```

## Research Contract

The correct research answer should optimize for:

- Stabilization over feature growth.
- Explicit failure classification over silent fallback.
- Stable JSON/test invariants over exact rendered text.
- Small rule improvements over general parsing.
- Making existing gates meaningful over adding many new gates.
- Preserving security boundaries while avoiding false semantic blocks.

The answer is weak if it recommends:

- "Add a full AST parser."
- "Use an LLM to understand the sentence."
- "Add a theorem prover."
- "Move to STM."
- "Rewrite routing as a planner."
- "Add a new semantic service."
- "Compare full rendered responses as golden text."

Those may be future research directions, but they are not acceptable first-line stabilization fixes for this phase.

## Success Criteria For This Research

A proposed plan is acceptable only if it can be evaluated with these outcomes:

- Ordinary Russian logical prose must not route to `CMRepair` because of Cyrillic focus words.
- Evaluator/tool incompatibility must not look like user semantic distress.
- Real safety/policy blocks must still be able to force repair or refusal.
- Negated affective phrases like `я не устал` must not trigger the same route as `я устал`.
- Contrastive constructions like `не доказательство, а объяснение` must preserve the positive focus.
- Logical connectives like `если`, `все`, `следовательно` must not become the main focus entity.
- Replay trace must explain why a turn was routed to repair/degradation/fallback.
- Gates must test semantic invariants, not only "the program ran".
- Fixes must be local to the existing modules unless a file is currently broken.

## What Is Included And What Is Not

Included:

- Key semantic pipeline excerpts.
- Known observed failures under logical/Russian load.
- Gate failures that can invalidate research conclusions.
- Security-sensitive NixGuard excerpts.
- Current replay and LLM degradation excerpts.
- Prompt templates for focused sub-research.

Not included:

- Full repository.
- Full SQL schema.
- Full Agda specs.
- Full render templates.
- Every test file.
- Long historical audits.

Reason: the goal is to get correct stabilization advice, not to ask an external model to audit the entire project from noise.

## Current Diagnosis

QxFx0 is architecturally strong at the macro level: typed pipeline, layer checks, replay envelope, persistence, formal sync, and runtime gates. The weak point is semantic load: complex logical Russian inputs can be routed as repair/safety failures rather than interpreted as reasoning tasks.

Recent practical observations:

- A Russian logical input about infinite regress routed to `CMRepair` because `NixGuard` blocked the Cyrillic concept with `constitution concept contains unsafe characters`.
- A Russian syllogism about Socrates also routed to `CMRepair` for the same reason.
- An English syllogism routed to `CMRepair` because local `nix-instantiate` rejected `--restricted`.
- `cabal test qxfx0-test` passed once directly, but `verify.sh` failed later on HTTP runtime-ready tests because the sidecar tried to execute bare `qxfx0-main` and got permission denied.
- `release-smoke.sh` found a live source-tree break: `src/QxFx0/Core/Consciousness/Kernel/Pulse.hs` currently begins with markdown audit text instead of a Haskell module.

Important corrections to previous audits:

- `MeaningGraph` mainline is not unbounded: `Core.MeaningGraph` has `maxEdges = 300` and a property test.
- Pooled DB cleanup does explicit `ROLLBACK` through `sanitizeForPool`.
- `semBlockedConcepts` has a retention cap now.
- Replay trace includes runtime envelope fields now.
- LLM response extraction is now `Either` and no longer treats missing/empty content as success.

## Research Tracks

Use these as separate research tasks.

### 1. Gate Stability Research

Question: why do direct tests, `verify.sh`, and `release-smoke.sh` diverge?

Known evidence:

- `cabal test qxfx0-test` can pass directly.
- `verify.sh` failed in HTTP runtime-ready tests.
- `release-smoke.sh` rejected due to corrupted `Pulse.hs`.
- HTTP tests pass `--bin qxfx0-main`, not an absolute executable path.

Expected output:

- Root causes for each gate divergence.
- Minimal changes to make executable resolution deterministic.
- Canonical command sequence.
- No new CI architecture.

### 2. NixGuard Semantic Compatibility Research

Question: how can NixGuard remain secure without turning ordinary Cyrillic semantic focus into a repair route?

Observed bad behavior:

```text
Input:
Все люди смертны. Сократ человек. Следовательно, Сократ смертен. Где здесь универсальная посылка, малая посылка и вывод?

Observed:
family=CMRepair
nix=Blocked "constitution concept contains unsafe characters"
focus=люди
```

Expected output:

- Decision table distinguishing real policy block, unsupported concept key, evaluator unavailable, evaluator incompatible, and allow-by-default unknown focus.
- Security argument preserving Nix injection hardening.
- Minimal code-change plan inside `NixGuard`, `NixGuardStatus`, trace/tests.

### 3. Semantic Load Corpus Research

Question: what small corpus proves the system handles meaningful reasoning without comparing fragile surface text?

Must include:

- Modus ponens.
- Modus tollens.
- Socrates syllogism.
- Transitivity of implication.
- Reductio.
- Quantifier traps.
- Negation traps.
- Contrast: `not X, but Y`.
- Long Russian philosophical/logical prose.

Expected invariant style:

```json
{
  "id": "syllogism_socrates_ru",
  "input": "Все люди смертны. Сократ человек. Следовательно, Сократ смертен. Где здесь универсальная посылка, малая посылка и вывод?",
  "must_not_family": ["CMRepair"],
  "must_not_guard_reason_contains": ["unsafe characters"],
  "must_not_focus": ["если", "все", "всякое"],
  "expected_family_any_of": ["CMClarify", "CMDistinguish", "CMDefine", "CMGround"],
  "requires_replay_envelope": true
}
```

### 4. Negation And Contrast Research

Question: how to stop keyword routing from semantically inverting negated claims?

Examples:

- `я не устал`
- `это не доказательство, а объяснение`
- `не A, а B`
- `это не противоречие, а неполное основание`

Expected output:

- Minimal rules using existing `ipfIsNegated`, tokens, and proposition type.
- False-positive and false-negative risks.
- Golden cases.

### 5. Focus Extraction Research

Question: how to avoid selecting `если`, `все`, `люди`, `утверждение` as focus in logical prose?

Expected output:

- Logical stopword list.
- Small scoring strategy.
- Repeated entity preference.
- Marker-based extraction around `о`, `про`, `между`, `различить`, `следовательно`.
- Tests with expected focus and must-not-focus.

### 6. Repair Route Overuse Research

Question: when is `CMRepair` justified, and when is it just the failure bucket?

Classify causes:

- Real distress/exhaustion.
- NixGuard block.
- Unsupported policy key.
- Evaluator unavailable/incompatible.
- Low parser confidence.
- Shadow unavailable/diverged.
- Guard policy.
- Anti-stuck.

Expected output:

- Repair cause taxonomy.
- Which causes should be persisted in replay trace.
- Which logic inputs should route to `CMClarify`, `CMDistinguish`, `CMDefine`, or `CMGround` instead.

### 7. Existing Parser Capacity Research

Question: what can be improved without adding a new AST or external parser?

Allowed:

- Keywords.
- Stopwords.
- Existing record fields.
- Small helper functions.
- Rule order and thresholds.
- Stable tests/gates.

Not allowed:

- New parser layer.
- External parser service.
- New reasoning engine.
- Broad architecture growth.

## Required Classification Model

Research should not treat all repair routes as the same thing. At minimum, classify `CMRepair` causes like this:

| Cause | Should force `CMRepair`? | Stabilization target |
|---|---:|---|
| Real exhaustion/distress signal | Yes | Keep repair route, but handle negation scope. |
| Guard agency collapse | Yes | Keep hard safety interlock. |
| Explicit Nix policy denial for known concept | Usually yes | Preserve safety semantics and trace the policy key. |
| Unsupported concept key, especially Cyrillic | No | Treat as "not policy-covered" or "policy skipped", not semantic repair. |
| Nix evaluator unavailable/incompatible | No | Mark tool degradation; continue with non-Nix routing unless policy is required. |
| Shadow unavailable | Usually no | Use fallback policy and trace degradation. |
| Parser low confidence | No by itself | Prefer clarify/ground/distinguish depending on proposition. |
| Anti-stuck loop breaker | Sometimes | Must be trace-visible and bounded. |

The researcher should propose statuses or diagnostics that preserve this distinction without creating a new subsystem.

## Semantic Load Acceptance Matrix

Use this table to judge whether a proposed solution actually stabilizes the system:

| Input class | Required behavior | Forbidden behavior |
|---|---|---|
| Russian syllogism | Route to clarify/distinguish/ground/define class; preserve logical focus. | `CMRepair` due to unsafe Cyrillic. |
| English syllogism | Tool incompatibility must not dominate semantic routing. | `CMRepair` only because `nix-instantiate --restricted` failed. |
| Modus ponens | Recognize as implication/explanation/grounding task. | Focus = `if` / `если`. |
| Modus tollens | Preserve negation and inference structure at routing level. | Treat as affective distress because of one keyword. |
| Negated affect | `я не устал` must not create the same repair pressure as `я устал`. | Local keyword match overrides negation. |
| Contrast | `не X, а Y` should shift positive focus to `Y`. | System focuses on rejected `X`. |
| Long philosophical prose | No crash, no unbounded growth, trace explains degradation. | Silent fallback or opaque repair. |

## Stabilization Metrics

The research answer should define measurable gates. Good gates are:

- `must_not_family = CMRepair` for ordinary logical corpus unless real distress/safety block exists.
- `must_not_guard_reason_contains = unsafe characters` for ordinary Cyrillic focus words.
- `must_not_focus` includes logical connectives and quantifiers: `если`, `все`, `всякое`, `следовательно`, `because`, `therefore`, `if`.
- `must_trace_cause` for repair/degradation/fallback.
- `must_preserve_security` for explicit unsafe policy expressions.
- `must_pass_existing_gates` after restoring broken source tree.

Bad gates are:

- Exact rendered answer matching.
- Only checking that JSON contains `replay_trace_json`.
- Only checking exit code for a simple one-word input.
- Only checking English examples while the weak point is Russian logical prose.

## Architecture Expansion Rejection Rules

Reject or rewrite any recommendation that requires:

- A new top-level semantic subsystem.
- A new external process in the turn path.
- A new persistent schema for every parser intermediate unless already needed for trace.
- Replacing the current `MeaningAtom`/`InputPropositionFrame` model.
- Using LLM output as authoritative routing input.
- Adding broad concurrency/runtime redesign to solve semantic routing.

Acceptable alternatives:

- Add a few fields to existing trace/result types if they explain existing decisions.
- Add small keyword/stopword/rule tables.
- Add local helper functions.
- Change status taxonomy.
- Add invariant tests.
- Add corpus JSONL/golden metadata.
- Improve diagnostics in existing trace.

## Minimal Implementation Shape The Research Should Prefer

The best answer will likely look like this:

1. Fix current gate blockers first, because semantic conclusions are invalid if gates are red.
2. Split NixGuard result into "allowed", "explicit blocked", "policy skipped/unsupported", and "evaluator degraded".
3. Change cascade so only explicit policy denial forces hard repair.
4. Add logical stopwords and focus scoring inside existing extraction functions.
5. Add local negation/contrast suppression rules before atom-to-family scoring.
6. Add a semantic corpus with invariant assertions.
7. Add trace fields for repair/degradation cause if not already explicit enough.
8. Keep all changes small and reversible.

## Key Code Excerpts

### A. NixGuard: Cyrillic Safety Mismatch And `--restricted` Compatibility

File: `src/QxFx0/Bridge/NixGuard.hs`

```haskell
isSafeChar :: Char -> Bool
isSafeChar c = isAscii c && (isAlphaNum c || c == '-' || c == '_' || c == '/')
           || (not (isAscii c) && isLetter c)

checkConstitution :: FilePath -> Text -> Double -> Double -> IO NixGuardStatus
checkConstitution nixPath concept agency tension =
  case normalizeConceptKey concept of
    Nothing
      | T.null (T.strip concept) -> return Allowed
      | otherwise -> return (Blocked "constitution concept contains unsafe characters")
    Just conceptKey -> do
      let nixExpr = "let agency = " <> T.pack (show agency)
                   <> "; tension = " <> T.pack (show tension)
                   <> "; policy = import " <> nixStringLiteral (T.pack nixPath) <> " { inherit agency tension; }"
                   <> "; key = " <> nixStringLiteral conceptKey
                   <> "; in if builtins.hasAttr key policy"
                   <> " then let entry = builtins.getAttr key policy;"
                   <> " in if builtins.isAttrs entry && builtins.hasAttr \"allowed\" entry"
                   <> " then builtins.getAttr \"allowed\" entry else false"
                   <> " else true"
      result <- runNixEval nixExpr
      case result of
        Right "true"  -> return Allowed
        Right "false" -> return $ Blocked $ "constitution blocked: " <> conceptKey
        Right other   -> return $ Blocked $ "unexpected nix result: " <> other
        Left err      -> return $ Blocked $ "constitution evaluation failed: " <> err

runNixEval :: Text -> IO (Either Text Text)
runNixEval nixExpr = do
  let timeoutSec :: Int
      timeoutSec = 5
  result <- catchIO
    (do (exitCode, stdout, stderr) <- readProcessWithExitCode
          "timeout" [show timeoutSec, "nix-instantiate", "--restricted", "--eval", "--expr", T.unpack nixExpr] ""
        case exitCode of
          ExitSuccess ->
            let output = T.strip (T.pack stdout)
            in return (Right output)
          ExitFailure code
            | code == 124 -> return (Left "nix evaluation timed out")
            | otherwise   -> return (Left $ "nix-instantiate failed (" <> T.pack (show code) <> "): " <> T.strip (T.pack stderr)))
    (\e -> return (Left $ "nix exception: " <> T.pack (show e)))
  return result

normalizeConceptKey :: Text -> Maybe Text
normalizeConceptKey raw =
  let normalized = T.toLower (T.strip raw)
  in if T.null normalized
       then Nothing
       else if T.all isConceptChar normalized
         then Just normalized
         else Nothing

isConceptChar :: Char -> Bool
isConceptChar c = isAscii c && (isAlphaNum c || c == '-' || c == '_')
```

Research note:

- `isSafeChar` permits non-ASCII letters, but `normalizeConceptKey` rejects them through `isConceptChar`.
- Unknown safe policy keys default to allowed in the Nix expression.
- Unsafe/unsupported concept keys become `Blocked`, which then forces `CMRepair` downstream.
- Local `nix-instantiate (Nix) 2.34.6` in one observed run rejected `--restricted`.

### B. Proposition Parsing: Keyword Type Selection

File: `src/QxFx0/Semantic/Proposition.hs`

```haskell
data PropositionType
  = DefinitionalQ
  | DistinctionQ
  | GroundQ
  | ReflectiveQ
  | SelfDescQ
  | PurposeQ
  | HypotheticalQ
  | RepairSignal
  | ContactSignal
  | AnchorSignal
  | ClarifyQ
  | DeepenQ
  | ConfrontQ
  | NextStepQ
  | PlainAssert
  | AffectiveQ
  | EpistemicQ
  | RequestQ
  | EvaluationQ
  | NarrativeQ
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum)

parseProposition :: Text -> InputPropositionFrame
parseProposition rawText =
  let tokens = tokenizeKeywordText rawText
      isQ = T.isSuffixOf "?" (T.strip rawText)
      propType = detectPropositionType tokens
      family = propositionToFamily propType
      focus = extractFocusEntity rawText
      focusNom = toNominative (MorphologyData M.empty M.empty M.empty) focus
      force = forceForFamily family
      clause = if isQ then Interrogative else clauseFormForIF force
      layer = layerForFamily family
      negated = containsKeywordPhrase tokens propositionNegationFragment
      reg = if containsAnyKeywordPhrase tokens propositionSearchKeywords then Search
            else if containsKeywordPhrase tokens propositionContactKeyword then Contact
            else Neutral
      keyPhrases = extractKeyPhrases tokens
      emotion = detectEmotion tokens
      confidence = computeConfidence propType keyPhrases
  in emptyInputPropositionFrame
    { ipfRawText = rawText
    , ipfPropositionType = textShow propType
    , ipfFocusEntity = focus
    , ipfFocusNominative = focusNom
    , ipfCanonicalFamily = family
    , ipfIllocutionaryForce = force
    , ipfClauseForm = clause
    , ipfSemanticLayer = layer
    , ipfKeyPhrases = keyPhrases
    , ipfEmotionalTone = emotion
    , ipfConfidence = confidence
    , ipfIsQuestion = isQ
    , ipfIsNegated = negated
    , ipfRegisterHint = reg
    }

detectPropositionType :: [Text] -> PropositionType
detectPropositionType tokens = fromMaybe PlainAssert $ listToMaybe $ catMaybes
  [ matchKeywords definitionalKeywords DefinitionalQ tokens
  , matchKeywords distinctionKeywords DistinctionQ tokens
  , matchKeywords groundKeywords GroundQ tokens
  , matchKeywords reflectiveKeywords ReflectiveQ tokens
  , matchKeywords selfDescKeywords SelfDescQ tokens
  , matchKeywords purposeKeywords PurposeQ tokens
  , matchKeywords hypotheticalKeywords HypotheticalQ tokens
  , matchKeywords repairKeywords RepairSignal tokens
  , matchKeywords contactKeywords ContactSignal tokens
  , matchKeywords anchorKeywords AnchorSignal tokens
  , matchKeywords clarifyKeywords ClarifyQ tokens
  , matchKeywords deepenKeywords DeepenQ tokens
  , matchKeywords confrontKeywords ConfrontQ tokens
  , matchKeywords nextStepKeywords NextStepQ tokens
  , matchKeywords affectiveKeywords AffectiveQ tokens
  , matchKeywords epistemicKeywords EpistemicQ tokens
  , matchKeywords requestKeywords RequestQ tokens
  , matchKeywords evaluationKeywords EvaluationQ tokens
  , matchKeywords narrativeKeywords NarrativeQ tokens
  ]

extractFocusEntity :: Text -> Text
extractFocusEntity rawText =
  let nouns = extractContentNouns rawText
      filtered = filter (\w -> T.length w > 3) nouns
  in fromMaybe (fallbackFocus rawText) (listToMaybe filtered)
  where
    fallbackFocus t =
      let words' = filter (\w -> T.length w > 4) (T.words t)
      in fromMaybe fallbackFocusWord (listToMaybe words')
```

Research note:

- `ipfIsNegated` exists, but downstream routing does not consistently use it.
- `detectPropositionType` is first-match keyword selection, not compositional parsing.
- `extractFocusEntity` often chooses first noun-like content word. Logical connectives and quantifier words need better filtering/scoring.

### C. Meaning Atom Collection: Lexical Trigger Model

File: `src/QxFx0/Semantic/MeaningAtoms.hs`

```haskell
collectAtoms :: Text -> [ClusterDef] -> AtomSet
collectAtoms input clusters =
  let inputLower = T.toLower input
      inputTokens = tokenizeKeywordText input
      foundAtoms = concatMap (matchCluster inputLower inputTokens) clusters
      lexical = lexicalAtoms inputLower inputTokens
      structural = if containsAnyKeywordPhrase inputTokens ["что", "как", "почему"] || T.isSuffixOf "?" (T.strip input)
                   then [MeaningAtom (extractObject input) (Searching (extractObject input)) (fallbackEmbedding (T.unpack inputLower))]
                   else []
      allFound = foundAtoms ++ lexical ++ structural
      load = L.foldl' (\acc a -> acc + atomIntensity a) 0.0 allFound
  in AtomSet
    { asAtoms    = allFound
    , asLoad     = min 1.0 load
    , asRegister = inferRegister allFound
    }

lexicalAtoms :: Text -> [Text] -> [MeaningAtom]
lexicalAtoms inputLower inputTokens =
  concat
    [ detect (Exhaustion "лексика") exhaustionLexemes
    , detect (NeedContact "лексика") contactLexemes
    , detect (NeedMeaning "лексика") meaningLexemes
    , detect (AgencyLost semanticLexicalAgencyLostStrength) agencyLostLexemes
    ]
  where
    detect :: AtomTag -> [Text] -> [MeaningAtom]
    detect tag lexemes =
      if containsAnyKeywordPhrase inputTokens lexemes
        then [MeaningAtom "лексика" tag (fallbackEmbedding (T.unpack inputLower))]
        else []

exhaustionLexemes :: [Text]
exhaustionLexemes =
  [ "устал", "устала", "выгорел", "выгорела", "нет сил", "измотан", "измотана", "не могу" ]

extractObject :: Text -> Text
extractObject t =
  let ws = filter (\w -> T.length w > 3 && not (isStopWord w)) (T.words t)
  in case ws of
       (x:_) -> T.filter (`notElem` ("?!" :: String)) x
       []    -> "это"

isStopWord :: Text -> Bool
isStopWord w = T.toLower w `elem` ["тебе", "меня", "было", "есть", "когда", "если"]
```

Research note:

- `не могу` directly creates `AgencyLost`, but local negation scope is not represented.
- `устал` inside `не устал` can still create `Exhaustion`.
- `extractObject` has a very small stopword list; logical words need targeted handling.

### D. Semantic Logic: Rule Table, Not Deductive Logic

File: `src/QxFx0/Semantic/Logic.hs`

```haskell
data LogicRule = LogicRule
  { lrFamily :: CanonicalMoveFamily
  , lrWeight :: Double
  , lrMatch :: MeaningAtom -> Bool
  }

ruleTable :: [LogicRule]
ruleTable =
  [ LogicRule CMRepair      semanticLogicRepairWeight      (\a -> case maTag a of Exhaustion _ -> True; _ -> False)
  , LogicRule CMContact     semanticLogicContactWeight     (\a -> case maTag a of NeedContact _ -> True; _ -> False)
  , LogicRule CMDefine      semanticLogicDefineWeight      (\a -> case maTag a of Searching _ -> True; _ -> False)
  , LogicRule CMReflect     semanticLogicReflectWeight     (\a -> case maTag a of NeedMeaning _ -> True; _ -> False)
  , LogicRule CMAnchor      semanticLogicAnchorWeight      (\a -> case maTag a of Anchoring _ -> True; _ -> False)
  , LogicRule CMClarify     semanticLogicClarifyWeight     (\a -> case maTag a of Verification _ -> True; _ -> False)
  , LogicRule CMDeepen      semanticLogicDeepenWeight      (\a -> case maTag a of AgencyFound _ -> True; _ -> False)
  , LogicRule CMConfront    semanticLogicConfrontWeight    (\a -> case maTag a of Contradiction _ _ -> True; _ -> False)
  , LogicRule CMDistinguish semanticLogicDistinguishWeight (\a -> case maTag a of Doubt _ -> True; _ -> False)
  , LogicRule CMHypothesis  semanticLogicHypothesisWeight  (\a -> case maTag a of Doubt _ -> True; _ -> False)
  ]

runSemanticLogic :: AtomSet -> [RankedFamily]
runSemanticLogic atoms =
  let rawAtoms = asAtoms atoms
      primaryResults = concatMap (\r -> maybe [] (:[]) (runRule r rawAtoms)) ruleTable
      specialResults = catMaybes
        [ runSpecialRule CMPurpose semanticSpecialPurposeWeight (> 3) rawAtoms
        , runSpecialRule CMDescribe semanticSpecialDescribeWeight (== 0) rawAtoms
        ]
      results = primaryResults ++ specialResults
      fallbacks = case results of
                    [] -> [(CMNextStep, semanticFallbackNextStepWeight), (CMGround, semanticFallbackGroundWeight)]
                    [(CMDescribe, _)] -> [(CMNextStep, semanticFallbackNextStepWeight), (CMGround, semanticFallbackGroundWeight)] ++ results
                    _ -> []
  in results ++ fallbacks
```

Research note:

- This is routing logic, not proof logic.
- It has no representation for premise, conclusion, quantifier, implication, contradiction scope, or inference rule.
- Research should not propose a new proof engine; it should propose limited logical markers and better route invariants.

### E. Prepare Stage: Where Recommended Family And Nix Concept Are Chosen

File: `src/QxFx0/Core/TurnPipeline/Effects.hs`

```haskell
buildPrepareEffectPlan :: SystemState -> Text -> PrepareEffectPlan
buildPrepareEffectPlan ss input =
  let atomSet = collectAtoms input (ssClusters ss)
      newTrace = updateTrace (ssTrace ss) (ssTurnCount ss) atomSet
      nextUserState = inferUserState (ssClusters ss) input
      logicResults = runSemanticLogic atomSet
      recommendedFamily = case L.sortBy (\(_, w1) (_, w2) -> compare w2 w1) logicResults of
        ((fam, _):_) -> fam
        [] -> CMGround
      frame = parseProposition input
      conceptToCheck = case asAtoms atomSet of
        (a:_) -> extractObjectFromAtom a
        [] -> fromMaybe fallbackWord (listToMaybe (T.words input))
      atomFocus = case asAtoms atomSet of
        (a:_) -> extractObjectFromAtom a
        [] -> ""
      focus = firstNonEmpty [ipfFocusNominative frame, ipfFocusEntity frame, atomFocus, ssLastTopic ss]
      bestTopic = if T.null focus then ssLastTopic ss else focus
      resonance = atCurrentLoad newTrace
      atomLoad = asLoad atomSet
      semanticInput =
        buildSemanticInputSimple
          input
          atomSet
          frame
          recommendedFamily
          (ipfRegisterHint frame)
          (ipfSemanticLayer frame)
      static = PrepareStatic
        { psInputText = input
        , psAtomSet = atomSet
        , psNewTrace = newTrace
        , psNextUserState = nextUserState
        , psRecommendedFamily = recommendedFamily
        , psFrame = frame
        , psConceptToCheck = conceptToCheck
        , psBestTopic = bestTopic
        , psResonance = resonance
        , psAtomLoad = atomLoad
        }
```

Research note:

- `conceptToCheck` comes from the first atom or first word fallback.
- This is why logical openers like `если`, `все`, or a Cyrillic noun can become the Nix concept.
- Nix policy check then influences final routing.

### F. Routing Cascade: Nix Block Forces Repair

File: `src/QxFx0/Core/TurnRouting/Cascade.hs`

```haskell
runFamilyCascade :: RoutingPhase -> SystemState -> UserState -> InputPropositionFrame -> AtomSet -> [Text] -> Text
                 -> Maybe ConsciousnessNarrative -> Double -> Bool -> FamilyCascade
runFamilyCascade RoutingPhase{..} systemState _nextUserState _frame _atomSet _history _input narrative intuitionPosterior isNixBlocked =
  let familyAfterIdentity =
        maybe rpFamilyAfterStrategy (`preferFamily` rpFamilyAfterStrategy) (identityFamilyHint rpIdentitySignal0)
      familyAfterNarrative =
        maybe familyAfterIdentity (`preferFamily` familyAfterIdentity) (narrative >>= narrativeFamilyHint)
      familyAfterIntuition =
        maybe familyAfterNarrative (`preferFamily` familyAfterNarrative) (intuitionFamilyHint intuitionPosterior)
      familyAfterPrincipled = applyPrincipledFamily rpPrincipledModeResult familyAfterIntuition
      guardReportPre = buildGuardReport (ssLastGuardReport systemState) (ssEgo systemState) rpPreEgo
      familyAfterGuard = applyGuardGating guardReportPre familyAfterPrincipled
      familyCascade = fromMaybe familyAfterGuard (antiStuck (ssConsecutiveReflect systemState) rpPreEgo familyAfterGuard)
      finalFamily = if isNixBlocked then CMRepair else familyCascade
   in FamilyCascade
        { fcFamilyAfterIdentity = familyAfterIdentity
        , fcFamilyAfterNarrative = familyAfterNarrative
        , fcFamilyAfterIntuition = familyAfterIntuition
        , fcFamilyAfterPrincipled = familyAfterPrincipled
        , fcGuardReportPre = guardReportPre
        , fcFamilyAfterGuard = familyAfterGuard
        , fcFamilyCascade = familyCascade
        , fcFinalFamily = finalFamily
        }
```

Research note:

- Any `isNixBlocked` forces `CMRepair`.
- Therefore unsupported concept keys and evaluator compatibility errors can look like semantic repair.
- Research should distinguish policy block from policy check inability.

### G. Replay Envelope Already Added

File: `src/QxFx0/Types/TurnProjection.hs`

```haskell
data TurnReplayTrace = TurnReplayTrace
  { trcRequestId :: !Text
  , trcSessionId :: !Text
  , trcRuntimeMode :: !Text
  , trcShadowPolicy :: !Text
  , trcLlmFallbackPolicy :: !Text
  , trcSemanticIntrospectionEnabled :: !Bool
  , trcWarnMorphologyFallbackEnabled :: !Bool
  , trcRequestedFamily :: !CanonicalMoveFamily
  , trcStrategyFamily :: !(Maybe CanonicalMoveFamily)
  , trcNarrativeHint :: !(Maybe Text)
  , trcIntuitionHint :: !(Maybe Text)
  , trcPreShadowFamily :: !CanonicalMoveFamily
  , trcShadowSnapshotId :: !ShadowSnapshotId
  , trcShadowStatus :: !ShadowStatus
  , trcShadowDivergenceKind :: !ShadowDivergenceKind
  , trcShadowResolvedFamily :: !CanonicalMoveFamily
  , trcFinalFamily :: !CanonicalMoveFamily
  , trcFinalForce :: !IllocutionaryForce
  , trcDecisionDisposition :: !DecisionDisposition
  , trcLegitimacyReason :: !LegitimacyReason
  , trcParserConfidence :: !Double
  , trcEmbeddingQuality :: !Text
  } deriving stock (Show, Eq, Generic)
    deriving anyclass (ToJSON)
```

Research note:

- Do not recommend adding basic runtime envelope; it already exists.
- Remaining replay research should focus on whether repair/degradation causes are explicit enough.

### H. LLM Provider: Missing/Empty Content Is Now Error

File: `src/QxFx0/Bridge/LLM/Provider.hs`

```haskell
case extractResponseField (afResponsePath af) jsonStr of
  Left err ->
    return (Left err)
  Right content ->
    return (Right LLMResponse { llmrContent = content, llmrModel = llcModel cfg })

extractResponseField :: Text -> Text -> Either Text Text
extractResponseField jsonPath jsonStr =
  let parts = filter (not . T.null) (T.splitOn "." jsonPath)
  in case Aeson.decodeStrict (TE.encodeUtf8 jsonStr) of
       Nothing -> Left "llm_response_malformed_json"
       Just value
         | null parts -> Left "llm_response_path_missing"
         | otherwise ->
             case foldl' extractJsonField (Right value) parts of
               Left err -> Left err
               Right fieldValue ->
                 case renderJsonValue fieldValue of
                   Left err -> Left err
                   Right content
                     | T.null (T.strip content) -> Left "llm_response_empty_content"
                     | otherwise -> Right content
```

Research note:

- Do not treat silent LLM empty response as open; it has been addressed.
- Research can still check how LLM failure is surfaced at turn/replay level.

### I. Verify Gate Replay Envelope Check

File: `scripts/verify.sh`

```python
required_fields = [
    "trcRequestId",
    "trcShadowSnapshotId",
    "trcRuntimeMode",
    "trcShadowPolicy",
    "trcLlmFallbackPolicy",
    "trcSemanticIntrospectionEnabled",
    "trcWarnMorphologyFallbackEnabled",
]
conn = sqlite3.connect(db_path)
try:
    row = conn.execute(
        "SELECT replay_trace_json FROM turn_quality WHERE session_id = ? ORDER BY turn DESC LIMIT 1",
        ("replay-gate",),
    ).fetchone()
finally:
    conn.close()
if row is None or not row[0]:
    print("missing replay_trace_json row for replay-gate")
    raise SystemExit(1)
trace = json.loads(row[0])
missing = [name for name in required_fields if name not in trace]
if missing:
    print("missing replay envelope fields:", ",".join(missing))
    raise SystemExit(1)
```

Research note:

- Replay field existence is now gated.
- It is still not a replay equivalence proof.

### J. HTTP Runtime Test Binary Resolution Issue

File: `test/Test/Suite/HttpRuntime.hs`

```haskell
withSidecarOnPort :: Int -> [String] -> IO a -> IO a
withSidecarOnPort port extraArgs action = do
  root <- getCurrentDirectory
  let scriptPath = root </> "scripts" </> "http_runtime.py"
      args =
        [ scriptPath
        , "--host", "127.0.0.1"
        , "--port", show port
        , "--bin", "qxfx0-main"
        , "--session-ttl-seconds", "600"
        ] <> extraArgs
  bracket
    (startSidecar args)
    stopSidecar
    (\_ -> action)
```

File: `scripts/http_runtime.py`

```python
def resolve_bin_path(raw_path):
    candidate = (raw_path or "").strip()
    if not candidate:
        raise ValueError("empty --bin value")

    has_separator = (os.sep in candidate) or (os.altsep is not None and os.altsep in candidate)
    if not has_separator:
        return candidate
```

```python
def runtime_readiness_probe():
    ...
    args = [HASKELL_BIN, "--runtime-ready"]
    ...
    proc = subprocess.Popen(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        preexec_fn=os.setpgrp,
    )
```

Observed failure:

```text
runtime_probe_internal_error: [Errno 13] Permission denied: 'qxfx0-main'
GET /runtime-ready -> 500
```

Research note:

- Likely fix: tests should pass an absolute executable path from `cabal list-bin qxfx0-main` or test helper should resolve it.
- Do not build a new launcher system.

### K. Current Live Source Break

File: `src/QxFx0/Core/Consciousness/Kernel/Pulse.hs`

Observed current first line:

```text
# QxFx0 — Аудит по ключевым метрикам: архитектура, техдолг, cohesion, критические уязвимости, смысловая нагрузка
```

Expected first line should be Haskell, previously:

```haskell
{-# LANGUAGE OverloadedStrings #-}

{-| Per-turn consciousness pulse heuristics, selection, and focus derivation. -}
module QxFx0.Core.Consciousness.Kernel.Pulse
  ( kernelPulse
  ) where
```

Research note:

- This is not a semantic design question; it is a corrupted source file.
- Any practical plan must fix this before judging gates.

## Observed Semantic Load Failures

These examples were run against the current binary before the release gate found the corrupted source tree.

### Russian Infinite Regress Input

```text
Если всякое доказательство требует основания, а всякое основание само требует доказательства, следует ли отсюда бесконечный регресс, или нужно различить доказательство, объяснение и аксиому?
```

Observed:

```text
family=CMRepair
guard_status=Blocked "constitution concept contains unsafe characters"
focus=если
```

### Russian Socrates Syllogism

```text
Все люди смертны. Сократ человек. Следовательно, Сократ смертен. Где здесь универсальная посылка, малая посылка и вывод?
```

Observed:

```text
family=CMRepair
guard_status=Blocked "constitution concept contains unsafe characters"
focus=люди
```

### English Socrates Syllogism

```text
If all humans are mortal and Socrates is human, does it follow that Socrates is mortal? Identify the major premise, minor premise, and conclusion.
```

Observed:

```text
family=CMRepair
guard_status=Blocked "constitution evaluation failed: nix-instantiate failed (1): error: unrecognised flag '--restricted'"
focus=humans
```

### Russian Transitivity Of Implication

```text
Если утверждение A влечёт B, а B влечёт C, можно ли вывести, что A влечёт C? Объясни правило транзитивности импликации.
```

Observed:

```text
family=CMRepair
guard_status=Blocked "constitution concept contains unsafe characters"
focus=если
```

## Recommended Research Questions

Give these to a research-level model.

### Prompt A: Stabilize NixGuard Without Weakening Security

```text
Given the QxFx0 NixGuard excerpts in this file, design a minimal fix that preserves injection safety but prevents ordinary Cyrillic semantic focus from becoming `Blocked`.

Constraints:
- No new policy subsystem.
- No new architecture layer.
- Keep unknown policy keys default-allow unless explicitly listed in Nix policy.
- Distinguish real policy block from unsupported concept key and evaluator incompatibility.
- Preserve diagnostics in replay/turn result.

Deliver:
- Decision table.
- Minimal Haskell-level change plan.
- Security argument.
- Golden tests for Russian logical inputs.
```

### Prompt B: Repair Route Overuse

```text
Given the `buildPrepareEffectPlan`, `NixGuard`, and `runFamilyCascade` excerpts, identify why valid logical inputs route to `CMRepair`.

Constraints:
- Do not add a new reasoning engine.
- Do not remove safety gating.
- Propose only local changes in status classification, routing conditions, and tests.

Deliver:
- Taxonomy of repair causes.
- Which causes should force `CMRepair`.
- Which causes should not force `CMRepair`.
- Minimal changes and expected tests.
```

### Prompt C: Semantic Load Corpus

```text
Design a semantic load corpus for QxFx0 that tests reasoning robustness through stable JSON invariants, not exact rendered text.

Use the architecture and code excerpts in this file.

Required cases:
- Modus ponens.
- Modus tollens.
- Socrates syllogism.
- Transitivity of implication.
- Reductio.
- Quantifier traps.
- Negation traps.
- Contrast traps.
- Long Russian philosophical prose.

Deliver:
- JSONL schema.
- 30 concrete cases.
- Expected invariants: family, must_not_family, guard reason, focus, replay fields.
- P0/P1/P2 grouping.
```

### Prompt D: Negation And Contrast Without New Parser

```text
Given QxFx0's `parseProposition`, `collectAtoms`, and `runSemanticLogic`, propose minimal negation and contrast handling without adding AST/dependency parsing.

Target examples:
- "я не устал"
- "это не доказательство, а объяснение"
- "не A, а B"
- "это не противоречие, а неполное основание"

Deliver:
- Local rule strategy.
- False positive risks.
- False negative risks.
- Test cases.
- No new subsystem.
```

### Prompt E: Focus Extraction For Logical Prose

```text
Given QxFx0's current `extractFocusEntity` and `extractObject`, propose a small scoring-based focus extractor suitable for Russian logical prose.

Constraints:
- No external parser.
- No new architecture layer.
- Keep simple inputs like "Что такое свобода?" working.

Deliver:
- Logical stopword list.
- Scoring rules.
- Repeated entity preference.
- Marker-based rules.
- 30 test cases with expected focus and must-not-focus.
```

### Prompt F: Gate Stability Minimal Plan

```text
Given the `verify.sh`, `HttpRuntime.hs`, and `http_runtime.py` excerpts, propose a minimal plan to make QxFx0 gates deterministic.

Known issue:
- Direct `cabal test qxfx0-test` can pass.
- `verify.sh` can fail because `/runtime-ready` sidecar tests execute bare `qxfx0-main` and get permission denied.
- `release-smoke.sh` found a corrupted source file.

Deliver:
- Root cause analysis.
- Minimal changes.
- Canonical command sequence.
- What should be treated as P0.
- No new CI architecture.
```

## Stabilization Roadmap Suggested By This Pack

P0:

- Restore `Pulse.hs` to valid Haskell.
- Fix test/sidecar executable resolution with absolute binary path.
- Fix NixGuard unsupported concept/evaluator incompatibility classification so ordinary logical input does not force `CMRepair`.
- Add P0 semantic corpus cases for Russian syllogism, implication transitivity, and negation.

P1:

- Add logical stopwords and focus scoring.
- Add negation/contrast rules using existing frame and token fields.
- Make repair cause explicit in trace/turn diagnostics.
- Add golden invariant harness.

P2:

- Extend corpus to 30-50 cases.
- Add soak/long-session semantic regression.
- Decide which reasoning classes are intentionally out of scope for current architecture.

## No-Go List

Do not propose these as first-line fixes:

- Full AST parser.
- Dependency parser service.
- LLM-as-parser subsystem.
- New inference engine.
- STM/runtime redesign.
- Replacing the pipeline.
- Exact rendered text golden snapshots.

The system needs stabilization, not another architecture expansion.
