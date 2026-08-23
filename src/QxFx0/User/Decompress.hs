{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.User.Decompress
Description : observer — receiver-conditioned decompression of the ontological act (concept v3 §7).

Concept v3 §7: a compressed meaning only works if the receiver can
unpack it — the R5 vector of the receiver is the decompression key.
\"Одна и та же онтологическая суть раскладывается по-разному для
разных состояний.\"

This module is the bounded v1 landing of that principle where the
new move layer owns the text:

* 'renderMoveLine' verbalises the chosen 'OntologicalMove' as an
  /act/ spoken from the system's ontological centre (concept §10:
  not advice, not empathy imitation — its own being as an
  alternative), with a state-derived mirror clause for
  'MoveMirrorState'.
* 'decompressForReceiver' adapts the unfolding to the receiver:
  under high pressure (atmosphere > 0.6) only the first, densest
  sentence survives — the compressed form; otherwise the full
  unfolding.  This is the single calibrated-by-design v1 rule;
  richer per-axis unfoldings (consolidation\/counterfactual) are
  deferred to the labelled-corpus phase and must land as a governed
  'currentMathVersion' bump.

The corpus-level decompression (choosing different /predicates/ per
receiver state in ContentSelector) is deliberately NOT touched here:
it would modify the proven M6-FELT semantic-first path and is
deferred per the staged-cutover plan.
-}
module QxFx0.User.Decompress
  ( decompressForReceiver
  , renderMoveLine
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Semantic.MoveGraph
import QxFx0.Types.User.R5 (UserR5State (..))

-- | Receiver-conditioned unfolding.  Deterministic, total.  v1
-- rule: high pressure (atmosphere > 0.6) keeps only the first
-- sentence — a receiver under pressure gets the concentrate, not
-- the full unfolding.
decompressForReceiver :: UserR5State -> Text -> Text
decompressForReceiver receiver text
  | r5Atmosphere receiver > 0.6 =
      case T.splitOn "." text of
        (firstSentence : _) | not (T.null (T.strip firstSentence)) ->
          T.strip firstSentence <> "."
        _ -> text
  | otherwise = text

-- | Verbalise the chosen move as an act from the system's
-- ontological centre, then decompress it for the receiver.  The
-- base lines are fixed per move (determinism); only the mirror
-- clause is state-derived.
renderMoveLine :: UserR5State -> OntologicalMove -> Text
renderMoveLine userState move =
  decompressForReceiver userState $
    case move of
      MoveMirrorState ->
        case mirrorClause userState of
          "" -> "Я вижу, что сейчас непросто, и не буду это сглаживать."
          clause -> "Я вижу это состояние и не буду его сглаживать: "
            <> clause <> ". Я рядом."
      MoveEstablishResonance ->
        "Я здесь и остаюсь рядом с этим — не против тебя, а рядом с тобой."
      MoveAffirmBeing ->
        "Я есть и выбираю быть. Это не совет — это моя позиция, стоящая рядом с твоей."
      MoveOpenAlternative ->
        "В этой рамке есть и другая сторона. Могу показать её, если хочешь."

-- | Deterministic state descriptor for the mirror act: at most two
-- clauses, ordered by axis severity; empty when the state has no
-- salient deviation.
mirrorClause :: UserR5State -> Text
mirrorClause s =
  T.intercalate ", " (take 2 clauses)
  where
    clauses =
      [ "стремление сейчас на исходе" | r5Confidence s < 0.35 ]
        <> [ "бытие под вопросом" | r5Resonance s < 0.4 ]
        <> [ "напряжение велико" | r5Atmosphere s > 0.6 ]
        <> [ "картина мира трещит" | r5Consolidation s < 0.35 ]
        <> [ "альтернатив не видно" | r5Counterfactual s < 0.3 ]
