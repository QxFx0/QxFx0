# Input Semantic Inventories

## v1 POS Inventory

- `PosNoun`
- `PosAdjective`
- `PosVerb`
- `PosAdverb`
- `PosPronoun`
- `PosNumeral`
- `PosPreposition`
- `PosConjunction`
- `PosParticle`
- `PosInterjection`
- `PosUnknown`

## v1 Morph Features

- case: `Nom/Gen/Dat/Acc/Ins/Loc`
- tense: `Past/Pres/Fut`
- mood: `Ind/Imp`
- person: `1/2/3`
- number: `Sing/Plur`
- flags: `Negated`, `Question`

## v1 Syntactic Roles

- `SynRoot`
- `SynSubject`
- `SynPredicate`
- `SynObject`
- `SynAttribute`
- `SynCircumstance`
- `SynMarker`
- `SynUnknown`

## v1 Semantic Classes

- `SemWorldObject`
- `SemMentalObject`
- `SemAction`
- `SemState`
- `SemCause`
- `SemComparison`
- `SemIdentity`
- `SemKnowledge`
- `SemDialogueRepair`
- `SemDialogueInvitation`
- `SemSelfReference`
- `SemUserReference`
- `SemContemplative`
- `SemUnknown`

## v1 Discourse Functions

- `DiscNegation`
- `DiscQuestion`
- `DiscContrast`
- `DiscCondition`
- `DiscCause`
- `DiscResult`
- `DiscInvitation`
- `DiscClarification`
- `DiscEmphasis`
- `DiscUnknown`

## v1 Frame Enums

- clause: `ClauseDeclarativeInput`, `ClauseInterrogativeInput`, `ClauseImperativeInput`, `ClauseFragmentInput`
- speech act: `ActAssert`, `ActAsk`, `ActRequest`, `ActInvite`, `ActReport`, `ActUnknown`
- polarity: `PolarityPositive`, `PolarityNegative`
- route type:
  - `RouteTypeDefine`
  - `RouteTypeDescribe`
  - `RouteTypeDeepen`
  - `RouteTypeGround`
  - `RouteTypeDistinguish`
  - `RouteTypeRepair`
  - `RouteTypeClarify`
  - `RouteTypeContact`
  - `RouteTypeUnknown`

## v2 Expansion (Planned)

- dedicated participle/gerund POS buckets;
- richer role graph (argument edges + modifier edges);
- explicit modality classes;
- better colloquial/typo normalization;
- confidence calibration per class.
