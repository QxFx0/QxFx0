# Promotion Selector Audit - 2026-07-19

## Eligible Predicate

- Overlay: `overlay-42c1335bbefc5d6bfe78ad359e685b6f8ca6517c29cd0da7a840c4d7bf430125`.
- Predicate id: `b597843143137551d6ebff0653f04c79c795db5cdd05aa3be1bdb3f28e2869e4`.
- Exact topic: `история`.
- Surface: `история связано с прошлое`.

## Selector Integration

`testActiveOverlayReachesSelectorOrRecordsLoss` in `test/Test/Suite/PromotionRuntime.hs` uses a temporary active-overlay DB and verifies:

- bootstrap merges the predicate into `ssDefinitionCorpus`;
- the exact topic contains it in `ContentSelector.csTopicPredicates`;
- the overlay surface maps to the predicate id in `CuratedOverlayRuntime`;
- an exact prompt `Что такое история?` reaches replay trace;
- the selector either attributes the predicate id or records an explicit loss reason.

## Actual A/B Decision

The pre-fix candidate trace for `overlay-topic-c3e8dff2f515d7d9` had `sdScore=0`, `below_score_threshold`, and no overlay attribution. After canonical atomization and semantic-space coverage, the same case reports:

- rendered surface: `история связана с прошлым`;
- `sdFieldAffinity=0.09158665769821862`;
- `sdActivationBonus=1`;
- `sdOntologyContribution=0.206`;
- `sdOovAtoms=[]`;
- final score: `0.14358956193926717`;
- `sdSelected=true`;
- overlay predicate id: `b597843143137551d6ebff0653f04c79c795db5cdd05aa3be1bdb3f28e2869e4`;
- selector policy/math versions are recorded in trace.

Final isolated A/B metrics: overlay usage `1`, unsupported assertions `0`, conflicts `0`, runtime failures/timeouts `0`, automated gate `true`. Activation remains blocked by `human_review_required`; no production activation was performed.
