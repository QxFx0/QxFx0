{-# LANGUAGE OverloadedStrings #-}

{-| Audit 2026-10-16 (p.11): fail-closed validation of persisted state.

Persisted JSON is a trust boundary: a corrupted or hand-edited store
must not silently drive the runtime.  'sanitizePersistedState' clamps
the value invariants the named vectors can violate, returns the
adjustments as notes (logged at load — visible, never silent), and is
otherwise the identity.  The trace-side invariant ('ceScalar') is
re-derived in 'ConatusEnergy''s 'FromJSON' instead, because the scalar
is a derived quantity, not a clamped one.
-}
module QxFx0.Bridge.StateSanitization
  ( sanitizePersistedState
  ) where

import Data.List (partition)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Self.SelfDivergence (SelfDivergenceTuning(..), defaultSelfDivergenceTuning)
import QxFx0.Types.ShadowDivergence (ShadowVetoState(..))
import QxFx0.Types.State.SelfState (SelfState(..))
import QxFx0.Types.State.System (SystemState(..), ssTurnCount)
import QxFx0.Types.User.R5
  ( UserR5ContourState(..)
  , ViabilityContour(..)
  , clampScore
  , defaultViabilityContour
  )

-- | Fail-closed sanitization of a decoded 'SystemState'.  Returns the
-- adjusted state plus one note per adjustment; an already-valid state
-- comes back value-unchanged with no notes.
sanitizePersistedState :: SystemState -> (SystemState, [Text])
sanitizePersistedState ss =
  let (veto, vetoNotes) = sanitizeShadowVeto (ssTurnCount ss) (ssShadowVetoState ss)
      (self, selfNotes) = sanitizeSelfState (ssSelfState ss)
      (contour, contourNotes) = sanitizeUserR5Contour (ssUserR5Contour ss)
      notes = vetoNotes <> selfNotes <> contourNotes
  in if null notes
       then (ss, [])
       else ( ss { ssShadowVetoState = veto
                 , ssSelfState = self
                 , ssUserR5Contour = contour
                 }
            , notes
            )

-- | @svsCount >= 0@; @0 <= svsWindowStart <=@ the loaded turn count.
--
-- A window start in the future keeps @currentTurn - start > 10@ false
-- for as long as the store says ('QxFx0.Core.TurnPipeline.Route.Build'
-- shadow-veto guard), so the veto stays bypassed and the window never
-- resets — the unbounded vector.  A count above the veto budget needs
-- no upper clamp: once the window expires the counter resets on its
-- own.
sanitizeShadowVeto :: Int -> ShadowVetoState -> (ShadowVetoState, [Text])
sanitizeShadowVeto turnCount state =
  let count' = max 0 (svsCount state)
      start' = max 0 (min turnCount (svsWindowStart state))
      notes =
        [ fieldNote "svsCount" (svsCount state) count'
        | count' /= svsCount state
        ]
          <> [ fieldNote "svsWindowStart" (svsWindowStart state) start'
             | start' /= svsWindowStart state
             ]
  in (state { svsCount = count', svsWindowStart = start' }, notes)

sanitizeSelfState :: SelfState -> (SelfState, [Text])
sanitizeSelfState state =
  let (window', notes) =
        sanitizeWindow
          (sdtWindow defaultSelfDivergenceTuning)
          "selfDivergenceWindow"
          (selfDivergenceWindow state)
  in (state { selfDivergenceWindow = window' }, notes)

sanitizeUserR5Contour :: UserR5ContourState -> (UserR5ContourState, [Text])
sanitizeUserR5Contour contour =
  let (baseline', baselineNotes) = sanitizeBaseline (u5Baseline contour)
      (window', windowNotes) =
        sanitizeWindow
          (vcDivergenceWindow defaultViabilityContour)
          "u5DivergenceWindow"
          (u5DivergenceWindow contour)
  in ( contour { u5Baseline = baseline'
               , u5DivergenceWindow = window'
               }
     , baselineNotes <> windowNotes
     )

-- | Non-finite baselines silently degenerate the relative contour
-- branch ('QxFx0.Types.User.R5.outsideViabilityContour'), so they
-- become 'Nothing'; finite ones take the runtime's own 'clampScore'.
sanitizeBaseline :: Maybe Double -> (Maybe Double, [Text])
sanitizeBaseline Nothing = (Nothing, [])
sanitizeBaseline (Just v)
  | isNaN v || isInfinite v = (Nothing, ["u5Baseline: non-finite -> Nothing"])
  | v /= clamped = (Just clamped, [fieldNote "u5Baseline" v clamped])
  | otherwise = (Just v, [])
  where
    clamped = clampScore v

-- | Drop non-finite samples and keep the newest-first @bound@ head
-- (the 'QxFx0.Self.SelfDivergence.pushDivergenceSample' /
-- 'QxFx0.Types.User.R5.pushR5Sample' convention).
sanitizeWindow :: Int -> Text -> [Double] -> ([Double], [Text])
sanitizeWindow bound label samples =
  let (finite, nonFinite) = partition isFinite samples
      kept = take (max 1 bound) finite
      notes =
        [ label <> ": dropped " <> tshow (length nonFinite) <> " non-finite sample(s)"
        | not (null nonFinite)
        ]
          <> [ label <> ": " <> tshow (length finite) <> " -> " <> tshow (length kept) <> " samples"
             | length kept < length finite
             ]
  in (kept, notes)
  where
    isFinite x = not (isNaN x) && not (isInfinite x)

fieldNote :: Show a => Text -> a -> a -> Text
fieldNote label before after =
  label <> ": " <> tshow before <> " -> " <> tshow after

tshow :: Show a => a -> Text
tshow = T.pack . show
