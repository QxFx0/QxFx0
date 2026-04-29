# Input Semantic Mapping

## Corpus Hint -> Runtime Mapping

The research corpus uses `expected_route_family_hint` labels that are not runtime enums.
This table defines canonical mapping to runtime proposition classes.

| Corpus hint                | PropositionType               | CanonicalMoveFamily |
|---------------------------|-------------------------------|---------------------|
| `dialogue.invite`         | `DialogueInvitationQ`         | `CMDeepen`          |
| `qa.knowledge`            | `ConceptKnowledgeQ`           | `CMDefine`          |
| `qa.self`                 | `SelfKnowledgeQ` / `SelfStateQ` | `CMDescribe`     |
| `logic.cause_result`      | `WorldCauseQ`                 | `CMGround`          |
| `logic.comparison`        | `ComparisonPlausibilityQ`     | `CMDistinguish`     |
| `ellipsis.fragment`       | context-dependent             | `CMClarify`         |
| `single_word`             | `ContemplativeTopic` or clarify | `CMDeepen` / `CMClarify` |
| `ambiguity.challenge`     | context-dependent             | `CMClarify`         |
| `normalization.input_error` | normalized target class      | target family       |

Technical labels:

- `morphology.*`, `reference.*`, `modifier.*`, `syntax.*`, `semantics.*` are parser diagnostics.
- These are not route families and must not be emitted as final runtime family values.

## Route Hint Tags

The input frame layer emits tags:

- `dialogue_invitation`
- `concept_knowledge`
- `self_state`
- `generative_prompt`
- `contemplative_topic`
- `misunderstanding`
- `comparison_plausibility`
- `world_cause`
- `location_formation`
- `self_knowledge`
- `unknown`

`QxFx0.Semantic.Proposition` converts these tags to `PropositionType` and then to `CanonicalMoveFamily`.

## Precedence Rules

1. High-confidence frame tag -> proposition hint.
2. Existing keyword detector fallback.
3. Conservative fallback (`CMClarify`/`CMGround`) if both are uncertain.

This keeps backward compatibility while shifting routing authority toward structured input semantics.
