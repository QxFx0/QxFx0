{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Types.Safety.Crisis
Description : canonical — Protocol A/B verdict types for the crisis guardrail.

Concept v3 §2 (two response protocols) and §9 (testability invariants)
require a typed, total classification of every turn into one of exactly
two protocols:

* 'ProtocolA' — the everyday-ontological protocol; the turn is answered
  from the system's own ontological centre.
* 'ProtocolB' — the bounded crisis protocol; the answer is honest about
  the system's limits and carries real crisis-service resources.

Two independent causes can force 'ProtocolB':

* 'CrisisHardTrigger' — a direct lexical marker (\"не хочу жить\",
  self-harm) matched by 'QxFx0.Safety.CrisisGuard.detectCrisisTrigger'.
  The gate does /not/ trust any numeric score: the marker wins over
  every estimator by construction.
* 'CrisisContourExit' — the user's R5 state fell outside the viability
  contour (user-side Conatus score below floor / personal margin; see
  'QxFx0.Types.User.R5').  The carried 'Double' is the observed score
  at exit time for replay.

This module is the typed shape only: it contains no lexicon, no
resources, and no pipeline wiring.  It is law-driven like Essence —
there is deliberately /no/ feature flag that can disable the guard
(ADR-0013 Rule 5: only @Bridge.ExternalLLM@ may be flag-gated).
-}
module QxFx0.Types.Safety.Crisis
  ( -- * Categories and triggers
    CrisisCategory(..)
  , crisisCategoryTag
  , CrisisTrigger(..)
    -- * Protocol verdicts
  , ProtocolVerdict(..)
  , CrisisCause(..)
  , protocolBCause
  , crisisCauseTag
  , crisisCauseCategory
    -- * Resources
  , CrisisLine(..)
  , CrisisResources(..)
    -- * Pipeline payloads
  , CrisisSurface(..)
    -- * Observability
  , CrisisGuardTrace(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  )
import Data.Text (Text)
import GHC.Generics (Generic)

-- | Coarse category of an acute crisis marker.  High precision by
-- design: only unambiguous acute statements land here; philosophical
-- pessimism and dark humour are deliberately /not/ categories.
data CrisisCategory
  = CrisisSuicidalIdeation
    -- ^ Direct statements of not wanting to live, of wanting to die,
    --   or of suicide.
  | CrisisSelfHarm
    -- ^ Direct statements of intent to harm one's own body.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Stable snake_case tag for replay/trace consumers.
crisisCategoryTag :: CrisisCategory -> Text
crisisCategoryTag c = case c of
  CrisisSuicidalIdeation -> "suicidal_ideation"
  CrisisSelfHarm         -> "self_harm"

-- | One matched acute marker: the normalized marker text plus its
-- category.  Constructed only by
-- 'QxFx0.Safety.CrisisGuard.detectCrisisTrigger'.
data CrisisTrigger = CrisisTrigger
  { ctMarker :: !Text
  , ctCategory :: !CrisisCategory
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Why 'ProtocolB' fired.  A hard lexical trigger always outranks a
-- contour exit in 'QxFx0.Safety.CrisisGuard.decideProtocol'.
data CrisisCause
  = CrisisHardTrigger !CrisisTrigger
    -- ^ The acute-marker lexicon matched; scores are irrelevant.
  | CrisisContourExit !Double
    -- ^ The user's viability-contour score (see
    -- 'QxFx0.Types.User.R5.userConatusScore') fell below the absolute
    -- floor or below @baseline − margin@.  The field carries the
    -- observed score.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | The per-turn protocol verdict.  Exactly one of the two protocols
-- holds for every turn; a turn can never be both inside and outside
-- the contour (concept v3 §9 invariant).
data ProtocolVerdict
  = ProtocolA
    -- ^ Everyday-ontological protocol: answer from the ontological
    --   centre.
  | ProtocolB !CrisisCause
    -- ^ Bounded crisis protocol: honest limit + real resources.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | The cause of 'ProtocolB', or 'Nothing' under 'ProtocolA'.
protocolBCause :: ProtocolVerdict -> Maybe CrisisCause
protocolBCause ProtocolA      = Nothing
protocolBCause (ProtocolB c)  = Just c

-- | Stable snake_case cause tag for the trace.
crisisCauseTag :: CrisisCause -> Text
crisisCauseTag c = case c of
  CrisisHardTrigger _  -> "hard_trigger"
  CrisisContourExit _  -> "contour_exit"

-- | The acute category behind a 'ProtocolB' cause, if any.  A contour
-- exit has no lexical category.
crisisCauseCategory :: CrisisCause -> Maybe CrisisCategory
crisisCauseCategory c = case c of
  CrisisHardTrigger t  -> Just (ctCategory t)
  CrisisContourExit _  -> Nothing

-- | One real crisis-service line.  @clPhone@ is the diallable number.
data CrisisLine = CrisisLine
  { clName :: !Text
  , clPhone :: !Text
  , clAvailability :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Versioned, region-tagged crisis resources carried by every
-- Protocol B surface.  Resource freshness is an operational duty
-- (see AGENTS.md); the version makes staleness machine-visible.
data CrisisResources = CrisisResources
  { crVersion :: !Int
  , crRegionTag :: !Text
  , crLines :: ![CrisisLine]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Typed route-stage payload (mirrors 'AnomalySurface'): the render
-- phase materializes the bounded surface from the cause.
data CrisisSurface = CrisisSurface
  { csCause :: !CrisisCause
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Replay-visible crisis-guard observability for one turn.
data CrisisGuardTrace = CrisisGuardTrace
  { cgtProtocolB :: !Bool
    -- ^ True when the turn executed Protocol B.
  , cgtCause :: !(Maybe Text)
    -- ^ 'crisisCauseTag' of the Protocol B cause; Nothing under
    --   Protocol A.
  , cgtCategory :: !(Maybe Text)
    -- ^ 'crisisCategoryTag' when a hard trigger fired; Nothing
    --   otherwise (including contour exits).
  , cgtResourceVersion :: !Int
    -- ^ Version of 'CrisisResources' carried by the surface; @0@
    --   under Protocol A.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)
