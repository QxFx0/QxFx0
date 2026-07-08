# ADR-0052: Relation Graph & External Knowledge Sources

**Status:** Proposed
**Date:** 2026-07-08
**Replaces:** acknowledged tech debt item #3 from post-audit fix round
**Related:** ADR-0009 (Field), Axis 2 Spreading Activation (composeFromActivation), SemanticNetwork design, Substrate module

---

## Problem Statement

QxFx0's knowledge graph operates in two disconnected layers:

| Layer | Edges | Semantics | Source |
|-------|-------|-----------|--------|
| `AtomGraph` / `Relation` (`AtomStore.hs`) | ~50 | Rich: `RelationType` (47 variants), `verbText`, grammatical case, `rationale`, `counter`, `synthesis`, `relRuOriginal` | Hand-coded in Haskell `relationStore` |
| `SemanticNetwork` / `SemanticEdge` (`Network/Types.hs`) | ~50 explicit + ~78 substrate | Minimal: `(from, to, weight, cooc)` — no relation type, no verb, no rationale, no direction semantics | `seedFromCorpus` (shared-atom cooc) + `brain_kb.jsonl` (substrate cooc) |

**Key gaps identified in audit:**

1. **No relation corpus file** — all relations are hand-coded in Haskell `relationStore`. Adding a new topic requires recompiling.
2. **`SemanticEdge` has no relation semantics** — spreading activation operates on bare co-occurrence, not typed relations. Two parallel graph worlds with zero unification.
3. **No ontology/category hierarchy** — `ConceptCategory` exists but isn't used structurally in the graph. No formal taxonomy.
4. **No external knowledge ingestion pipeline** — `brain_kb → substrate edges` is co-occurrence-only. No pipeline for: relation corpus import, ontology import, curated edge import, LLM-extracted batch import, cross-domain graph import.
5. **No edge weighting rationale** — substrate edges fixed 0.3, corpus edges `sharedCount/10`. No confidence, no provenance beyond `EdgeSource`.
6. **No versioning or provenance** — `ActivationStep` has `asSource` but `SemanticEdge` only has `EdgeSource`. No timestamp, no author, no confidence, no version chain.
7. **30-topic hardcoded ceiling** — expanding knowledge means editing Haskell source.

---

## Design

### Layer 1: Unify the Two Graph Worlds

**Central insight:** `AtomGraph`/`Relation` is the *authoritative* relational store
(rich semantics, hand-crafted, 50 edges on 30 topics). `SemanticNetwork`/`SemanticEdge`
is the *spreading-activation substrate* (fast traversal, multi-hop, 128 edges on
~318 atoms). The two must be unified so that:

1. **Spread activation over typed relations**, not bare co-occurrence
2. **Rank traversal paths by Field-aligned relation-type bias**, not uniform decay
3. **Output predicates carry provenance back to the Relation that justified them**

#### 1a. Extend `SemanticEdge` with relation semantics

```haskell
-- BEFORE (Network/Types.hs:33-40):
data SemanticEdge = SemanticEdge
  { seFrom :: Text, seTo :: Text, seWeight :: Double
  , seCoOccurrence :: Int, seSource :: EdgeSource }

-- AFTER:
data SemanticEdge = SemanticEdge
  { seFrom :: Text, seTo :: Text, seWeight :: Double
  , seCoOccurrence :: Int, seSource :: EdgeSource
  , seRelationType :: Maybe RelationType    -- NEW: typed relation from AtomGraph
  , seVerb :: Maybe Text                    -- NEW: Russian verb text
  , seRationale :: Maybe Text               -- NEW: rationale from Relation
  , seConfidence :: Double                  -- NEW: edge confidence (0.0-1.0)
  , seProvenance :: EdgeProvenance          -- NEW: structured provenance
  }

data EdgeProvenance = EdgeProvenance
  { epSource :: EdgeSource
  , epCreatedAt :: UTCTime
  , epAuthor :: ProvenanceAuthor
  , epVersion :: Int
  , epDerivedFrom :: [RelationId]            -- back-link to Relation store
  }

data ProvenanceAuthor
  = AuthorCurator       -- hand-crafted
  | AuthorLLM Text      -- LLM model name
  | AuthorCorpus Text   -- corpus filename
  | AuthorSubstrate     -- brain_kb extraction
  deriving (Eq, Ord, Show, Read, Generic)
```

#### 1b. Build `SemanticNetwork` edges from `AtomGraph` relations

**Replace `seedFromCorpus` (`Network/Seed.hs:20-51`)** with `buildNetworkFromAtomGraph`:

```haskell
buildNetworkFromAtomGraph :: AtomGraph -> Map Text (Set Text) -> SemanticNetwork
```

Algorithm:
1. For each `Relation` in `agRelations`:
   - `seFrom = agAtomName (relFrom rel)`
   - `seTo = agAtomName (relTo rel)`
   - `seWeight = relationTypeWeight (relType rel)` — Field-weighted base score
   - `seRelationType = Just (relType rel)`
   - `seVerb = Just (relVerb rel)`
   - `seRationale = relRationale rel`
   - `seConfidence = 1.0` (hand-crafted = high confidence)
   - `seProvenance = EdgeProvenance ExplicitEdge now AuthorCurator 1 []`
2. Add topic→atom membership edges (weight 0.5) for each `topicAtoms` entry
3. Merge with substrate edges via existing `mergeSemanticNetworks`
   (explicit wins at same key; now carries full relation semantics)

**`relationTypeWeight`** maps each `RelationType` to a base weight:

```haskell
relationTypeWeight :: RelationType -> Double
relationTypeWeight = \case
  RelIs -> 1.0; RelDefines -> 1.0; RelIdentity -> 1.0
  RelClaims -> 0.9; RelVerifiedBy -> 0.9; RelPresupposes -> 0.85
  RelRequires -> 0.85; RelCauses -> 0.8; RelProduces -> 0.8
  RelImplies -> 0.8; RelIncludes -> 0.75; RelPartOf -> 0.75
  RelRelatedTo -> 0.7; RelAssociatedWith -> 0.7
  RelSignals -> 0.7; RelExpresses -> 0.7
  RelContrastsWith -> 0.6; RelDiffersFrom -> 0.6
  RelLimitedBy -> 0.6; RelDestroys -> 0.5; RelNegates -> 0.5
  RelNotReducibleTo -> 0.5; RelIsNot -> 0.5
  -- ... full 47-type mapping
  _ -> 0.5
```

This replaces the current `weight = sharedCount / 10.0` (co-occurrence-based) with
semantically meaningful weights derived from the hand-crafted relation types.

#### 1c. Relation-type-aware spreading activation

**Replace `spreadActivation` (`Network.hs:68-80`)** — current uniform decay:

```haskell
-- CURRENT: uniform decay
weight = act * seWeight * decay

-- NEW: Field-modulated, relation-type-aware:
weight = act * seWeight * decay * fieldModulation field seRelationType
```

Where `fieldModulation` applies the same `relationTypeBias` from
`PathFinder.hs:159-225` — different Field states amplify different relation types:

| Field dimension | Amplified relation types | Suppressed |
|-----------------|-------------------------|------------|
| High confidence | RelClaims, RelVerifiedBy, RelIdentity | RelContrastsWith, RelDiffersFrom |
| High counterfactual | RelContrastsWith, RelDiffersFrom, RelIsNot | RelIs, RelDefines |
| High resonance | RelSignals, RelExpresses, RelRelatedTo | — |
| High consolidation | RelPresupposes, RelRequires, RelImplies | RelDestroys, RelNegates |

This makes the spreading activation *Field-responsive*, not just a blind multi-hop
traversal. The same semantic network produces different activation patterns for a
confident system vs a doubting one.

---

### Layer 2: External Relation Corpus Format

**New data format:** `relations.jsonl` — a JSONL file of hand-curated or LLM-extracted relations.

```json
{
  "from": "свобода",
  "to": "ответственность",
  "type": "RelImplies",
  "verb": "предполагает",
  "rationale": "выбор без ответственности есть произвол",
  "counter": "ответственность без выбора есть принуждение",
  "synthesis": "свобода и ответственность взаимно обусловлены",
  "confidence": 0.95,
  "author": "curator",
  "version": 1
}
```

**Schema:**
| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `from` | Text | ✅ | Source atom name (must exist in `atomStore`) |
| `to` | Text | ✅ | Target atom name (must exist in `atomStore`) |
| `type` | `RelationType` enum | ✅ | One of 47 `RelationType` constructors |
| `verb` | Text | ✅ | Russian surface verb |
| `rationale` | Text | — | Justification in Russian |
| `counter` | Text | — | Counter-argument |
| `synthesis` | Text | — | Synthetic resolution |
| `confidence` | Double (0.0–1.0) | ✅ | Semantic confidence |
| `author` | `"curator"` or LLM model name | ✅ | Provenance |
| `version` | Int | ✅ | Monotonic version |

**Module:** `QxFx0.Semantic.Network.Ingest`

```haskell
ingestRelationCorpus :: FilePath -> AtomGraph -> IO [Relation]
-- Parses relations.jsonl, validates from/to against atomStore,
-- constructs Relation records with source = SeedFromPredicate (curated)
-- or LLMDiscovered (LLM author).

loadRelations :: IORef AtomGraph -> FilePath -> IO Int
-- Loads, ingests, merges into atomStore, rebuilds SemanticNetwork.
-- Returns count of new relations added.
```

**Bootstrap integration:**
```haskell
-- Bootstrap.hs, after initRuntimeContext:
_ <- loadRelations (ssAtomGraph state) "resources/knowledge/relations.jsonl"
```

---

### Layer 3: Ontology / Category Hierarchy

**New module:** `QxFx0.Semantic.Ontology`

**Data structure:**
```haskell
data OntologyNode = OntologyNode
  { onName :: Text
  , onCategory :: ConceptCategory   -- Philosophical | Social | Psychological | Physical | General
  , onParent :: Maybe Text          -- hierarchical parent
  , onChildren :: Set Text
  , onDepth :: Int                  -- distance from root
  }

data Ontology = Ontology
  { otNodes :: Map Text OntologyNode
  , otRoots :: Set Text             -- top-level categories
  , otEdges :: Map (Text, Text) OntologyEdge  -- is-a, part-of, related-to
  }

data OntologyEdgeType = OeIsA | OePartOf | OeRelatedTo
```

**Source:** `resources/knowledge/ontology.jsonl` (hand-curated + brain_kb-derived)

```json
{"name": "свобода", "category": "Philosophical", "parent": "абстрактное", "depth": 2}
{"name": "ответственность", "category": "Philosophical", "parent": "этика", "depth": 2}
{"name": "этика", "category": "Philosophical", "parent": "философия", "depth": 1}
```

**Usage in the graph:**
1. **Spreading activation bias:** edges between same-category nodes get +10% weight
   boost (semantic proximity heuristic).
2. **Predicate selection:** when `composeFromActivation` returns < 3 predicates,
   fill remaining slots from sibling topics (same parent, same category).
3. **Generic predicates for uncovered topics:** current `ConceptCategory`
   classification (`Content.hs:518-555`) uses lexical markers + suffixes; this
   can be replaced by ontology lookup: "if topic not in `coveredTopics`,
   find ontology node → look up category → use `genericDefinitionPredicates`."

---

### Layer 4: External Knowledge Ingestion Pipeline

**New module:** `QxFx0.Semantic.Network.Ingest` (extends Layer 2)

**Pipeline stages:**

```
External source → Parse → Validate → Admit → Merge → Rebuild network
```

#### 4a. Supported sources

| Source | Format | Admission gate | Confidence |
|--------|--------|----------------|------------|
| `relations.jsonl` | JSONL curated | Atom exists + non-self-ref + verb in whitelist | 0.95 (curated) |
| `ontology.jsonl` | JSONL curated | Valid category + parent exists | 1.0 |
| `brain_kb.jsonl` | JSONL (existing) | Layer filter + ≥2 triggers + `SubstrateCandidate.admitCandidate` | 0.3 |
| LLM extraction batch | JSONL from `--selfplay` output | `SubstrateCandidate.admitCandidate` | 0.4–0.7 (model-dep) |
| LLM `--discover <concept>` | Single API response | `admitCandidate` | 0.5 |

#### 4b. Admission pipeline per relation

```haskell
admitExternalRelation :: AtomGraph -> ExternalRelation -> Either RejectionReason Relation
admitExternalRelation ag er = do
  fromAtom <- note (RejAtomNotFound (erFrom er)) $ lookupAtom ag (erFrom er)
  toAtom <- note (RejAtomNotFound (erTo er)) $ lookupAtom ag (erTo er)
  guard (fromAtom /= toAtom) RejSelfReferential
  guard (erConfidence er >= 0.3) RejLowConfidence
  guard (erVerb er `elem` allowedVerbs) RejVerbNotInWhitelist
  pure Relation
    { relFrom = fromAtom, relTo = toAtom
    , relType = erType er, relVerb = erVerb er
    , relRuOriginal = erVerb er  -- or NLP-generated surface
    , ... source = if erAuthor == "curator" then SeedFromPredicate else LLMDiscovered
    }
```

#### 4c. Rebuild network on ingestion

```haskell
ingestAndRebuild :: IORef SystemState -> FilePath -> IO Int
ingestAndRebuild stateRef path = do
  state <- readIORef stateRef
  relations <- ingestRelationCorpus path (ssAtomGraph state)
  let newAtomGraph = foldl' (flip insertRelation) (ssAtomGraph state) relations
      newNetwork = buildNetworkFromAtomGraph newAtomGraph (ssTopicAtoms state)
                     `mergeSemanticNetworks` (ssSubstrateNetwork state)
  writeIORef stateRef state
    { ssAtomGraph = newAtomGraph
    , ssSemanticNetwork = newNetwork
    , ssContentSelector = buildContentSelector ... newNetwork ...
    }
  pure (length relations)
```

---

### Layer 5: Edge Provenance and Versioning

**`EdgeProvenance` record** (see Layer 1a) provides full traceability:

```haskell
data EdgeProvenance = EdgeProvenance
  { epSource :: EdgeSource       -- ExplicitEdge | SubstrateEdge | LLMEdge
  , epCreatedAt :: UTCTime
  , epAuthor :: ProvenanceAuthor
  , epVersion :: Int
  , epDerivedFrom :: [RelationId]  -- upstream relations this edge was derived from
  }
```

**Provenance-aware merge (`mergeSemanticNetworks` update):**
- Current: `M.union` with update-wins (substrate doesn't overwrite explicit)
- New: three-tier merge priority: `Curator > LLM > Substrate`. Within same tier,
  higher confidence wins. Within same confidence, higher version wins.
- Log conflicts to `snActivationLog` as `ActivationStep` entries with
  `asSource = EdgeMergeConflict`.

**Version bump on update:** When a curator edits a relation in `relations.jsonl` and
re-ingests, the new edge gets `epVersion = epVersion old + 1`. Old edges are archived
to `resources/knowledge/relations_archive.jsonl` rather than overwritten.

---

### Layer 6: Migration Plan

#### Phase I: Format and tools (2–3 дня)

1. **Create `resources/knowledge/relations.jsonl`** — export existing 50 relations
   from `AtomStore.hs` to the new format with `author: "curator"`, `confidence: 1.0`
2. **Create `resources/knowledge/ontology.jsonl`** — initial taxonomy for the
   **30 core topics only** (не ~260 концептов). ~260 концептов — deferred.
3. **Implement `QxFx0.Semantic.Ontology`** — `OntologyNode`, `Ontology`, lookup functions
4. **Implement `QxFx0.Semantic.Network.Ingest`** — `ingestRelationCorpus`, `loadOntology`

#### Phase II: Edge semantic upgrade (3–5 дней)

1. **Extend `SemanticEdge`** with `seRelationType`, `seVerb`, `seRationale`,
   `seConfidence`, `seProvenance` — **с persistence backward compatibility:**
   FromJSON tolerant к отсутствию новых полей (defaults: `Nothing`, 0.0, `EdgeProvenance ...`)
2. **Implement `buildNetworkFromAtomGraph`** — replaces `seedFromCorpus`
3. **Implement `relationTypeWeight`** — 47 магических чисел. Признаны
   произвольными без эмпирической валидации. Phase II shipped as
   `relationTypeWeight = 1.0` (uniform baseline) + TODO for corpus-driven sweep.
4. **Update `spreadActivation`** with `fieldModulation` (based on existing
   `relationTypeBias` from `PathFinder.hs:159-225`, not new magic numbers)
5. **Update `mergeSemanticNetworks`** with provenance-aware three-tier merge
6. **JSON serialization round-trip** с новыми полями
7. **Baseline comparison test:** для 10 фиксированных topic/queries сравнить
   `composeFromActivation` output до и после migration. Изменения допустимы, но
   должны быть задокументированы.

#### Phase III: Expand knowledge (ongoing)

1. **Curate 50–100 additional relations** — extend beyond the 30 core topics
2. **Ingest LLM-extracted relations** from `--selfplay` runs as `resources/knowledge/selfplay_relations.jsonl`
3. **Corpus-driven sweep of `relationTypeWeight`** — 47 весов должны быть
   эмпирически валидированы на production trace corpora (не magic numbers)
4. **Cross-domain import** — domain-specific relation schema for non-philosophical
   topics (science, art, law from the 28 domain atoms)
5. **Continuous ingestion** — live `--ingest` CLI command for runtime enrichment
   within a session

#### Phase IV: Ontology-driven generation (future)

1. **Replace lexical category classification** in `Content.hs:518-555` with
   ontology lookup
2. **Sibling-topic predicate borrowing** — when a topic has ≤1 predicate,
   borrow from ontology siblings
3. **Category-level generic predicates** — 5 categories (Philosophical, Social,
   Psychological, Physical, General) get 3–5 generic predicates each
4. **Ontology expansion to ~260 концептов** — deferred until Phase III curation
   pipeline proves sustainable

---

## Delivery Strategy

Phase I и Phase II разбиты на **4 отдельных PR** (не 2 фазы):

| PR | Содержание | Оценка |
|----|-----------|--------|
| PR #1 | `SemanticEdge` extension + FromJSON backward compat | 1 день |
| PR #2 | `buildNetworkFromAtomGraph` + baseline comparison tests | 1 день |
| PR #3 | `mergeSemanticNetworks` provenance-aware + `fieldModulation` в `spreadActivation` | 1 день |
| PR #4 | `Ingest.hs` + `Ontology.hs` + `relations.jsonl` + `ontology.jsonl` (30 топиков) + CLI | 2 дня |

**Total: ~2 недели, не 2–3 дня.**

---

## Review Amendments (2026-07-08)

1. **Оценки пересмотрены:** Phase I — 2–3 дня, Phase II — 3–5 дней, всего ~2 недели.
   Разбито на 4 PR вместо 2 фаз.
2. **Persistence backward compatibility — критический gate.** Старый `SemanticNetwork` без
   новых полей должен загружаться. `FromJSON` tolerant: отсутствующие поля → defaults
   (`Nothing`, `0.0`, `EdgeProvenance ExplicitEdge epoch AuthorCurator 1 []`).
3. **`relationTypeWeight` — uniform baseline.** 47 магических чисел заменены на
   `relationTypeWeight = const 1.0`. Field-модуляция через существующий `relationTypeBias`
   из `PathFinder.hs:159-225`, не новые числа. Corpus-driven sweep в Phase III.
4. **Онтология — 30 core topics only.** ~260 концептов deferred до Phase III, когда
   pipeline курирования доказан.
5. **Baseline comparison test — обязателен.** 10 фиксированных topic/queries: сравнить
   `composeFromActivation` до/после migration. Изменения допустимы, но должны быть
   задокументированы.
6. **Замена `seedFromCorpus` на `buildNetworkFromAtomGraph` — A/B на реальных диалогах.**
   Топология сети меняется с co-occurrence- на relation-type-based. Качество может как
   улучшиться, так и ухудшиться.

---

## Files Affected

| File | Change |
|------|--------|
| `src/QxFx0/Semantic/Network/Types.hs` | Extend `SemanticEdge`, add `EdgeProvenance`, `ProvenanceAuthor` |
| `src/QxFx0/Semantic/Network.hs` | `relationTypeWeight`, `fieldModulation`, updated `spreadActivation`, provenance-aware `mergeSemanticNetworks` |
| `src/QxFx0/Semantic/Network/Seed.hs` | Deprecate `seedFromCorpus` → replaced by `buildNetworkFromAtomGraph` |
| `src/QxFx0/Semantic/Network/Ingest.hs` | **New** — `ingestRelationCorpus`, `admitExternalRelation`, `loadRelations`, `ingestAndRebuild` |
| `src/QxFx0/Semantic/Ontology.hs` | **New** — `OntologyNode`, `Ontology`, `loadOntology`, category lookup |
| `src/QxFx0/Semantic/Content.hs` | Phase IV: replace lexical category with ontology lookup |
| `src/QxFx0/Core/TurnPipeline/Finalize/State.hs` | Call `buildNetworkFromAtomGraph` in `buildNextSystemState` |
| `src/QxFx0/Runtime/Session/Bootstrap.hs` | Load `relations.jsonl`, `ontology.jsonl` at boot |
| `app/CLI.hs` | New `--ingest <file>` command for runtime knowledge ingestion |
| `resources/knowledge/relations.jsonl` | **New** — curated relations corpus |
| `resources/knowledge/ontology.jsonl` | **New** — category hierarchy |
| `resources/knowledge/relations_archive.jsonl` | **New** — versioned archive |
| `test/Test/Suite/NetworkIngest.hs` | **New** — relation ingestion, ontology loading, provenance merge tests |
| `test/Test/Suite/Ontology.hs` | **New** — category lookup, sibling borrowing tests |
| `qxfx0.cabal` | Register new modules + test suites |

---

## Verification Gates

- [ ] **Phase I:** `cabal test qxfx0-test-fast` passes (existing 1332+ tests)
- [ ] **Phase I:** `relations.jsonl` is a complete, valid export of the 50 existing
  `relationStore` entries
- [ ] **Phase I:** `ontology.jsonl` has complete taxonomy for all 30 core topics
- [ ] **Phase II:** `buildNetworkFromAtomGraph` produces a `SemanticNetwork` with
  `seRelationType` populated for all explicit edges
- [ ] **Phase II:** **Persistence backward compatibility:** старая persisted `SemanticNetwork`
  без новых полей десериализуется (FromJSON tolerant — defaults для `seRelationType`,
  `seVerb`, `seRationale`, `seConfidence`, `seProvenance`)
- [ ] **Phase II:** **Baseline comparison:** для 10 фиксированных topic/queries сравнить
  `composeFromActivation` output до и после migration. Изменения задокументированы.
- [ ] **Phase II:** `spreadActivation` with `fieldModulation` produces different
  activation patterns for confident vs doubting Field states (deterministic test)
- [ ] **Phase II:** JSON round-trip: `SemanticNetwork` with new fields serializes
  and deserializes correctly
- [ ] **Phase II:** Provenance-aware merge: curator edge (conf 0.95) overwrites
  LLM edge (conf 0.5) at same key
- [ ] **Phase III:** Ingestion of 10 new test relations from JSONL → 10 new edges
  in both `AtomGraph` and `SemanticNetwork`
- [ ] **Phase III:** `--ingest resources/knowledge/test_relations.jsonl` CLI
  command works end-to-end
- [ ] **Phase IV:** Unknown topic with ontology entry → generic predicate from
  matching category (not hardcoded fallback)
- [ ] No regression: `contentDensityGate` (≥50 edges, ≥15 nodes) still passes
  after migration

---

## Non-Goals (explicitly deferred)

1. **NLP-based surface generation from relations** — `verbalizeRelation` in
   `AtomStore.hs:2290` returns stored `relRuOriginal` text. No template-based or
   NLG surface generation from structured relation data. This is a separate
   sentence-planning feature.
2. **Automatic ontology extraction from brain_kb** — the ontology is hand-curated
   initially. Automated extraction from brain_kb triggers is deferred until a
   reliable clustering pipeline exists.
3. **Multi-language relation corpus** — Russian only. English translations
   (`relEnOriginal`, `spEn`) are stored but not used for graph edges.
4. **Real-time graph visualization or query API** — the relation graph is an
   internal runtime structure, not an external service.
5. **Graph database (Neo4j, etc.)** — the graph is in-memory Haskell. External
   graph DB integration is deferred.