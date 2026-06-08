{-# LANGUAGE StrictData #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Core.GenericPropositionAdmission
Description : Generic admission logic for proposition triggers (P1-1 refactor)

This module eliminates ~2000 lines of duplicated code across 18 Proposition*Admission
modules by providing a single parameterized admission function.

Each specific admission module now only needs to provide:
- A list of safe trigger labels
- Accessor functions for the trigger record fields

The three-guard admission logic (authoritative → admit; triggerAlreadySafe → preserve;
otherwise → suppress) is implemented once here.
-}
module QxFx0.Types.Admission.GenericPropositionAdmission
  ( PropositionAdmissionConfig(..)
  , admitPropositionTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Observability (TruthContractStatus)
import QxFx0.Types.TruthContract (truthContractIsAuthoritative)

-- | Configuration for a specific proposition admission type.
-- Parameterized over:
--   @input@ - the admission input type (contains TruthContractStatus)
--   @trigger@ - the raw trigger type (has label and matched fields)
--   @admitted@ - the admitted triggers result type
--   @decision@ - the admission decision type (3 constructors)
data PropositionAdmissionConfig input trigger admitted decision = PropositionAdmissionConfig
  { -- | Extract TruthContractStatus from input
    pacGetTruthContract :: input -> TruthContractStatus
    -- | Get the label field from a trigger
  , pacTriggerLabel :: trigger -> Text
    -- | Get the matched field from a trigger
  , pacTriggerMatched :: trigger -> Bool
    -- | Set the matched field on a trigger
  , pacSetTriggerMatched :: Bool -> trigger -> trigger
    -- | List of trigger labels that are safe even when matched
  , pacSafeLabels :: [Text]
    -- | Constructor for admitted result (raw, processed, decision)
  , pacAdmittedCtor :: [trigger] -> [trigger] -> decision -> admitted
    -- | Decision constructor: admit raw
  , pacDecisionAdmitRaw :: decision
    -- | Decision constructor: preserve ambiguous
  , pacDecisionPreserveAmbiguous :: decision
    -- | Decision constructor: suppress strong triggers
  , pacDecisionSuppressStrong :: decision
  }

-- | Generic admission function implementing the three-guard logic.
-- This replaces 18 nearly-identical functions across Proposition*Admission modules.
admitPropositionTriggers
  :: PropositionAdmissionConfig input trigger admitted decision
  -> input
  -> [trigger]
  -> admitted
admitPropositionTriggers config input rawTriggers
  | truthContractIsAuthoritative (pacGetTruthContract config input) =
      pacAdmittedCtor config rawTriggers rawTriggers (pacDecisionAdmitRaw config)
  | all (triggerAlreadySafe config) rawTriggers =
      pacAdmittedCtor config rawTriggers rawTriggers (pacDecisionPreserveAmbiguous config)
  | otherwise =
      pacAdmittedCtor config
        rawTriggers
        (map (softenTrigger config) rawTriggers)
        (pacDecisionSuppressStrong config)

-- | Check if a trigger is already safe (not matched or in safe list)
triggerAlreadySafe
  :: PropositionAdmissionConfig input trigger admitted decision
  -> trigger
  -> Bool
triggerAlreadySafe config rawTrigger =
  not (pacTriggerMatched config rawTrigger)
    || pacTriggerLabel config rawTrigger `elem` pacSafeLabels config

-- | Soften a trigger by setting matched=False if it's not already safe
softenTrigger
  :: PropositionAdmissionConfig input trigger admitted decision
  -> trigger
  -> trigger
softenTrigger config rawTrigger
  | triggerAlreadySafe config rawTrigger = rawTrigger
  | otherwise = pacSetTriggerMatched config False rawTrigger

